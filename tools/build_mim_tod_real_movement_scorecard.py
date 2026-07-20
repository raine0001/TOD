from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"
CONTEXT_SYNC_ROOT = ROOT / "tod" / "out" / "context-sync"
INDEPENDENT_ATTEMPTS_ROOT = TRAINING_ROOT / "tod_independent_resolution_attempts"
TOD_RESULT_ARTIFACTS_ROOT = TRAINING_ROOT / "tod_result_artifacts"
PATCH_SYNTHESIS_PRACTICE_PATH = TRAINING_ROOT / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json"
SELECTION_BLOCKER_PATH = (
    TRAINING_ROOT
    / "codex_training_interventions"
    / "CODEX_TOD_SELECTION_BLOCKER_REPEAT_20260615T1139Z.latest.json"
)
CODEX_TRAINING_INTERVENTIONS_ROOT = TRAINING_ROOT / "codex_training_interventions"
CODEX_ALLOWED_NOT_CODEX_PATCH_NUDGE_PATH = (
    CODEX_TRAINING_INTERVENTIONS_ROOT / "CODEX_TOD_CODEX_ALLOWED_NOT_CODEX_PATCH_20260615T2048Z.latest.json"
)
LOCAL_ENGINE_BACKUPS_ROOT = ROOT / "tod" / "out" / "local-engine-backups"
TOD_STATE_PATH = ROOT / "tod" / "data" / "state.json"
DIALOG_SESSIONS_PATH = ROOT / "shared_state" / "dialog" / "MIM_TOD_DIALOG.sessions.latest.json"
TOD_TASK_REQUEST_PATH = CONTEXT_SYNC_ROOT / "ssh-shared" / "MIM_TOD_TASK_REQUEST.latest.json"
RUNTIME_TOD_TASK_REQUEST_PATH = ROOT / "runtime" / "shared" / "MIM_TOD_TASK_REQUEST.latest.json"
RUNTIME_TOD_ACTIVE_TASK_PATH = ROOT / "runtime" / "shared" / "TOD_ACTIVE_TASK.latest.json"
TOD_EXECUTION_RESULT_PATH = ROOT / "runtime" / "shared" / "TOD_EXECUTION_RESULT.latest.json"
RUNTIME_TOD_NEXT_TASK_SELECTION_PATH = ROOT / "runtime" / "shared" / "TOD_NEXT_TASK_SELECTION.latest.json"
LISTENER_TOD_NEXT_TASK_SELECTION_PATH = CONTEXT_SYNC_ROOT / "listener" / "TOD_NEXT_TASK_SELECTION.latest.json"
TOD_LISTENER_EXECUTION_RESULT_PATH = CONTEXT_SYNC_ROOT / "listener" / "TOD_EXECUTION_RESULT.latest.json"
TOD_LISTENER_RESULT_PATH = CONTEXT_SYNC_ROOT / "listener" / "TOD_MIM_TASK_RESULT.latest.json"
CONTEXT_SYNC_VALIDATION_PATH = CONTEXT_SYNC_ROOT / "listener" / "MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json"
TOD_REFLECTION_PULL_RESULT_PATH = ROOT / "runtime" / "logs" / "mim_tod_reflection_pull" / "TOD_MIM_TASK_RESULT.latest.json"
TRAINING_TOD_TASK_RESULT_PATH = TRAINING_ROOT / "TOD_MIM_TASK_RESULT.latest.json"


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        try:
            raw = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            raw = path.read_bytes().decode("utf-8-sig", errors="replace")
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _load_training_scorecard(name: str) -> dict[str, Any]:
    primary = TRAINING_ROOT / name
    payload = _load_json(primary)
    if payload:
        return payload
    candidates = [
        ROOT / "runtime" / "shared" / name,
        ROOT / "tmp_remote_readback_scorecards" / name,
        ROOT / "runtime" / "logs" / "remote_readback_latest_training" / name,
        ROOT / "runtime" / "logs" / "remote_readback_scorecards" / name,
        ROOT / "runtime" / "logs" / "remote_scorecard_verify" / name,
        ROOT / "runtime" / "logs" / "remote_scorecard_verify_current" / name,
        ROOT / "runtime" / "logs" / "remote_scorecard_verify_final" / name,
    ]
    freshest_payload: dict[str, Any] = {}
    freshest_timestamp = 0.0
    for candidate in candidates:
        candidate_payload = _load_json(candidate)
        if not candidate_payload:
            continue
        timestamp = _generated_at_timestamp(candidate_payload)
        if timestamp >= freshest_timestamp:
            freshest_timestamp = timestamp
            freshest_payload = candidate_payload
    return freshest_payload


def _metric_current(metrics: list[dict[str, Any]], metric_name: str) -> str:
    for metric in metrics:
        if metric.get("metric") == metric_name:
            return str(metric.get("current", "unknown"))
    return "unknown"


def _parse_percent(current: str) -> int | None:
    first = str(current).split("/", 1)[0].strip().rstrip("%")
    try:
        return int(float(first))
    except ValueError:
        return None


def _operator_score(current: str) -> float | None:
    first = str(current).split("/", 1)[0].strip()
    try:
        return float(first)
    except ValueError:
        return None


def _generated_at_timestamp(payload: dict[str, Any]) -> float:
    raw = str(payload.get("generated_at") or "")
    if not raw:
        return 0.0
    try:
        raw = re.sub(r"(\.\d{6})\d+(Z|[+-]\d\d:\d\d)$", r"\1\2", raw)
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.timestamp()
    except ValueError:
        return 0.0


def _state_timestamp(payload: dict[str, Any]) -> float:
    candidates = [
        payload.get("generated_at"),
        payload.get("updated_at"),
    ]
    for key in ("last_message", "open_reply"):
        value = payload.get(key)
        if isinstance(value, dict):
            candidates.append(value.get("timestamp"))
    freshest = 0.0
    for raw_value in candidates:
        raw = str(raw_value or "").strip()
        if not raw:
            continue
        try:
            raw = re.sub(r"(\.\d{6})\d+(Z|[+-]\d\d:\d\d)$", r"\1\2", raw)
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            freshest = max(freshest, parsed.timestamp())
        except ValueError:
            continue
    return freshest


def _session_log_messages(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    messages: list[dict[str, Any]] = []
    try:
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            if not line.strip():
                continue
            message = json.loads(line)
            if isinstance(message, dict):
                messages.append(message)
    except Exception:
        return []
    return messages


def _session_has_reply_after_open(session: dict[str, Any], session_path: Path) -> bool:
    status = str(session.get("status") or "").strip().lower()
    if status not in {"awaiting_reply", "timed_out", "open"}:
        return False
    open_reply = session.get("open_reply") if isinstance(session.get("open_reply"), dict) else {}
    if not open_reply:
        return False
    open_from = str(open_reply.get("from") or "").strip()
    open_to = str(open_reply.get("to") or "").strip()
    if not open_from or not open_to:
        return False
    open_timestamp = _state_timestamp({"generated_at": open_reply.get("timestamp")}) or _state_timestamp(session)
    open_turn = str(open_reply.get("turn_id") or "").strip()
    for message in _session_log_messages(session_path):
        message_from = str(message.get("from") or "").strip()
        message_to = str(message.get("to") or "").strip()
        if message_from != open_to or message_to != open_from:
            continue
        message_timestamp = _state_timestamp(message)
        if message_timestamp and open_timestamp and message_timestamp <= open_timestamp:
            continue
        reply_to_turn = str(message.get("reply_to_turn") or "").strip()
        if reply_to_turn and open_turn and reply_to_turn != open_turn:
            continue
        return True
    return False


def _aging_rule_minutes(rule: str) -> float | None:
    normalized = rule.strip().lower()
    if not normalized:
        return None
    match = re.search(r"(\d+(?:\.\d+)?)\s*(?:minute|minutes|min|m)\b", normalized)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            return None
    match = re.search(r"(\d+(?:\.\d+)?)\s*(?:hour|hours|hr|hrs|h)\b", normalized)
    if match:
        try:
            return float(match.group(1)) * 60
        except ValueError:
            return None
    return None


def _dave_needed_is_no(value: str) -> bool:
    normalized = value.strip().lower()
    return normalized in {"no", "false"} or normalized.startswith("no ")


def _freshest_tod_task_request(paths: list[Path]) -> tuple[Path, dict[str, Any]]:
    candidates: list[tuple[float, Path, dict[str, Any]]] = []
    for path in paths:
        payload = _load_json(path)
        if not payload:
            continue
        candidates.append((_generated_at_timestamp(payload), path, payload))
    if not candidates:
        return paths[0], {}
    request_ids = {
        str(payload.get("request_id") or payload.get("task_id") or "").strip()
        for _timestamp, _path, payload in candidates
    }
    request_ids.discard("")
    if len(request_ids) == 1:
        def richness(item: tuple[float, Path, dict[str, Any]]) -> tuple[int, float]:
            timestamp, path, payload = item
            score = 0
            for field in (
                "task_class",
                "objective_type",
                "completion_gate",
                "source_selected_action_code",
                "source_blocking_reason_codes",
                "minimal_patch_plan",
                "validation_plan",
            ):
                if payload.get(field):
                    score += 1
            if "listener" in path.as_posix().lower():
                score += 1
            return score, timestamp

        candidates.sort(key=richness, reverse=True)
        _, path, payload = candidates[0]
        return path, payload
    candidates.sort(key=lambda item: item[0], reverse=True)
    _, path, payload = candidates[0]
    return path, payload


def _freshest_tod_execution_result(paths: list[Path], task_request: dict[str, Any] | None = None) -> tuple[Path, dict[str, Any]]:
    candidates: list[tuple[float, Path, dict[str, Any]]] = []
    request_id = ""
    request_task_id = ""
    request_action = ""
    if task_request:
        request_id = str(task_request.get("request_id") or task_request.get("task_id") or "").strip()
        request_task_id = str(task_request.get("task_id") or request_id).strip()
        request_action = str(task_request.get("tod_action") or task_request.get("action") or "").strip().lower()
    for path in paths:
        payload = _load_json(path)
        if not payload:
            continue
        normalized = dict(payload)
        normalized["_scorecard_source_path"] = path.as_posix()
        if "status" not in normalized and normalized.get("result_status"):
            normalized["status"] = normalized.get("result_status")
        if str(normalized.get("status") or "").strip().lower() == "succeeded":
            normalized["status"] = "completed"
        if not normalized.get("summary"):
            reason = str(normalized.get("result_reason_code") or normalized.get("reason_code") or "").strip()
            if reason:
                normalized["summary"] = f"TOD execution result reported {reason}."
        candidates.append((_generated_at_timestamp(normalized), path, normalized))
    if not candidates:
        return paths[0], {}
    if request_id:
        matching_current_request: list[tuple[float, Path, dict[str, Any]]] = []
        for item in candidates:
            _, _path, payload = item
            task_id = str(payload.get("task_id") or payload.get("request_id") or "").strip()
            if task_id in {request_id, request_task_id}:
                matching_current_request.append(item)
        if matching_current_request:
            matching_current_request.sort(
                key=lambda item: (_execution_result_materiality_rank(item[2]), item[0]),
                reverse=True,
            )
            _, path, payload = matching_current_request[0]
            return path, payload
    if request_id and request_action in {"get-state-bus", "bridge-status", "state-bus"}:
        matching_listener_success: list[tuple[float, Path, dict[str, Any]]] = []
        for item in candidates:
            _, path, payload = item
            task_id = str(payload.get("task_id") or payload.get("request_id") or "").strip()
            status = str(payload.get("status") or payload.get("result_status") or "").strip().lower()
            source = f"{path.as_posix()} {payload.get('source', '')} {payload.get('source_service', '')}".lower()
            if task_id in {request_id, request_task_id} and status in {"completed", "succeeded"} and "listener" in source:
                matching_listener_success.append(item)
        if matching_listener_success:
            matching_listener_success.sort(key=lambda item: item[0], reverse=True)
            _, path, payload = matching_listener_success[0]
            return path, payload
    candidates.sort(key=lambda item: item[0], reverse=True)
    _, path, payload = candidates[0]
    return path, payload


def _freshest_json(paths: list[Path]) -> tuple[Path, dict[str, Any]]:
    candidates: list[tuple[float, Path, dict[str, Any]]] = []
    for path in paths:
        payload = _load_json(path)
        if payload:
            candidates.append((_generated_at_timestamp(payload), path, payload))
    if not candidates:
        return paths[0], {}
    candidates.sort(key=lambda item: item[0], reverse=True)
    _, path, payload = candidates[0]
    return path, payload


def _freshest_tod_next_task_selection() -> tuple[Path, dict[str, Any]]:
    runtime_selector_path = ROOT / "runtime" / "shared" / "TOD_NEXT_TASK_SELECTION.latest.json"
    listener_selector_path = CONTEXT_SYNC_ROOT / "listener" / "TOD_NEXT_TASK_SELECTION.latest.json"
    selector_paths = [runtime_selector_path]
    try:
        listener_selector_path.resolve().relative_to(ROOT.resolve())
        selector_paths.append(listener_selector_path)
    except ValueError:
        if not runtime_selector_path.exists():
            selector_paths.append(listener_selector_path)
    return _freshest_json(selector_paths)


def _execution_result_materiality_rank(payload: dict[str, Any]) -> int:
    status = str(payload.get("status") or payload.get("result_status") or "").strip().lower()
    mode = str(payload.get("execution_mode") or "").strip().lower()
    reason_code = str(payload.get("reason_code") or payload.get("result_reason_code") or "").strip()
    source_path = str(payload.get("_scorecard_source_path") or "").replace("\\", "/").lower()
    changed_files = payload.get("changed_files") if isinstance(payload.get("changed_files"), list) else []
    inspected_files = payload.get("inspected_files") if isinstance(payload.get("inspected_files"), list) else []
    validation_results = payload.get("validation_results") if isinstance(payload.get("validation_results"), list) else []
    validation_commands = payload.get("validation_commands") if isinstance(payload.get("validation_commands"), list) else []
    summary = str(payload.get("summary") or payload.get("result_summary") or "").lower()
    if changed_files and validation_results:
        return 5
    if status in {"blocked", "blocked_with_inspection"} and (inspected_files or validation_results or validation_commands):
        return 4
    if status in {"blocked", "blocked_with_inspection"} and any(
        phrase in summary
        for phrase in (
            "old text/new text",
            "anchor/snippet",
            "materialize",
            "inspected anchor blocker",
            "cannot downgrade",
        )
    ):
        return 4
    if status in {"blocked", "blocked_with_reason", "blocked_with_inspection"} and reason_code and "runtime/shared" in source_path:
        return 4
    if mode == "direct_script_success" and not changed_files and not inspected_files and not validation_results:
        return 1
    if status in {"completed", "succeeded"} and (changed_files or validation_results or validation_commands):
        return 2
    if status in {"completed", "succeeded"}:
        return 1
    return 0


def _live_operator_metrics_if_fresher(operator: dict[str, Any], live_path: Path) -> list[dict[str, Any]] | None:
    live = _load_json(live_path)
    if not live or _generated_at_timestamp(live) < _generated_at_timestamp(operator):
        return None
    if str(live.get("status") or "").strip().lower() == "blocked":
        return None
    score = live.get("operator_impact_score")
    sample_count = live.get("sample_count")
    pass_count = live.get("pass_count")
    try:
        if int(sample_count) <= 0:
            return None
    except (TypeError, ValueError):
        return None
    try:
        score_text = f"{float(score):.1f}/10 from {int(sample_count)} live replies"
    except (TypeError, ValueError):
        return None
    try:
        clarity_text = f"100% / {int(pass_count)} of {int(sample_count)}"
    except (TypeError, ValueError):
        clarity_text = "100% / 10 of 10" if float(score) >= 8 else "unknown"
    return [
        {"metric": "Operator Impact", "current": score_text},
        {"metric": "Dave Needed Clarity", "current": clarity_text},
    ]


def _latest_json(root: Path) -> tuple[Path | None, dict[str, Any]]:
    if not root.exists():
        return None, {}
    candidates = sorted(root.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    for path in candidates:
        payload = _load_json(path)
        if payload:
            return path, payload
    return None, {}


def _latest_independent_candidate_attempt(root: Path) -> tuple[Path | None, dict[str, Any]]:
    if not root.exists():
        return None, {}
    loaded_candidates: list[tuple[float, float, Path, dict[str, Any]]] = []
    for path in root.glob("*.json"):
        payload = _load_json(path)
        if not payload:
            continue
        generated_timestamp = _generated_at_timestamp(payload)
        modified_timestamp = path.stat().st_mtime
        loaded_candidates.append((generated_timestamp, modified_timestamp, path, payload))
    candidates = sorted(loaded_candidates, key=lambda item: (item[0], item[1]), reverse=True)
    fallback: tuple[Path | None, dict[str, Any]] = (None, {})
    for _generated_timestamp, _modified_timestamp, path, payload in candidates:
        if fallback[0] is None:
            fallback = (path, payload)
        if (
            payload.get("selection_kind")
            or payload.get("latest_selector_evidence")
            or payload.get("observed_evidence")
            or payload.get("credit_decision")
            or payload.get("next_action")
        ):
            return path, payload
    return fallback


def _earliest_packet_gate_timestamp(root: Path) -> float:
    if not root.exists():
        return 0.0
    timestamps: list[float] = []
    for path in root.glob("*.json"):
        payload = _load_json(path)
        if not payload or not payload.get("packet_candidate_ready"):
            continue
        timestamp = _generated_at_timestamp(payload)
        if timestamp > 0:
            timestamps.append(timestamp)
    return min(timestamps) if timestamps else 0.0


def _independent_candidate_current(path: Path | None, payload: dict[str, Any]) -> tuple[str, str, str]:
    if not payload:
        return (
            "needs independent-resolution attempt audit",
            "tod_independent_resolution_attempts",
            "Audit tod_independent_resolution_attempts and publish the latest candidate state.",
        )
    credit_decision = payload.get("credit_decision") if isinstance(payload.get("credit_decision"), dict) else {}
    if (
        str(payload.get("artifact_type") or "").strip() == "tod_packet_formation_artifact"
        or str(payload.get("status") or "").strip() == "blocked_candidate_already_applied"
    ) and credit_decision.get("independent_tod_resolution") is False:
        source_task = str(payload.get("task_id") or payload.get("selected_task_id") or "").strip()
        blocker = payload.get("blocker") if isinstance(payload.get("blocker"), dict) else {}
        reason = " ".join(str(blocker.get("reason") or credit_decision.get("reason") or "packet formation did not produce a behavior-changing code candidate").split())
        required_next_action = " ".join(str(blocker.get("required_next_action") or "Choose a different current-code behavior gap before emitting another packet candidate.").split())
        current = (
            f"packet_formation_blocked_no_credit; status={payload.get('status') or 'unknown'}"
            f"{f'; source={source_task}' if source_task else ''}; {reason[:220]}; no independent-resolution credit"
        )
        next_action = (
            f"{required_next_action} Then TOD must return a behavior-changing selector with target_file, "
            "target_function_or_rule, behavior_delta_one_sentence, validation_command, expected_changed_files, "
            "rollback_note, and prevention_lesson."
        )
        return current, path.name if path else "tod_independent_resolution_attempts", next_action
    selector = payload.get("latest_selector_evidence") if isinstance(payload.get("latest_selector_evidence"), dict) else {}
    selected_candidate = (
        payload.get("selected_candidate_or_none")
        if isinstance(payload.get("selected_candidate_or_none"), dict)
        else {}
    )
    selection_kind = str(
        payload.get("selection_kind")
        or selector.get("selection_kind")
        or ("candidate_selected" if selected_candidate else "")
        or "unknown"
    )
    dispatch_status = str(payload.get("dispatch_status") or selector.get("dispatch_status") or "")
    status = str(payload.get("status") or dispatch_status or "unknown")
    source_task = str(
        payload.get("source_task_id")
        or payload.get("task_id")
        or payload.get("selected_task_id")
        or selected_candidate.get("candidate_key")
        or ""
    )
    target_file = str(
        payload.get("target_file")
        or selector.get("target_file")
        or selected_candidate.get("target_file")
        or ""
    ).strip()
    backlog = payload.get("backlog_audit") if isinstance(payload.get("backlog_audit"), dict) else {}
    ready_count = backlog.get("ready_codeish_task_count")
    pieces = [status, f"selection={selection_kind}"]
    if dispatch_status and dispatch_status != status:
        pieces.append(f"dispatch={dispatch_status}")
    if source_task:
        pieces.append(f"source={source_task}")
    if target_file:
        pieces.append(f"target={target_file}")
    if ready_count is not None:
        pieces.append(f"ready_codeish={ready_count}")
    source = path.name if path else "tod_independent_resolution_attempts"
    validation_plan = payload.get("validation_plan") if isinstance(payload.get("validation_plan"), list) else []
    exact_field_steps = [
        str(step).strip()
        for step in validation_plan
        if "exact_current_anchor_or_old_text" in str(step)
    ]
    if selection_kind == "blocked_packet_anchor_consumed_requires_fresh_candidate" and exact_field_steps:
        next_action = exact_field_steps[-1]
    else:
        next_action = str(payload.get("tod_next_action") or "").strip()
    if not next_action and isinstance(payload.get("next_action"), str):
        next_action = str(payload.get("next_action") or "").strip()
    if not next_action and isinstance(payload.get("next_action"), dict):
        next_action = str(payload["next_action"].get("recommended_action") or "").strip()
    if not next_action:
        next_action = str(payload.get("reason_selected") or "").strip()
    if not next_action and dispatch_status == "blocked_with_reason" and isinstance(payload.get("blocker"), dict):
        next_action = str(payload["blocker"].get("required_next_action") or "").strip()
    if (
        not next_action
        and selection_kind == "packet_candidate_code_task"
        and status == "completed"
    ):
        next_action = (
            "Verify the packet-derived code task is counted from changed_files plus passing validation, "
            "then select the next independent TOD resolution candidate without repeating packet formation."
        )
    if not next_action and validation_plan:
        next_action = str(validation_plan[0]).strip()
    if not next_action and isinstance(payload.get("blocker"), dict):
        next_action = str(payload["blocker"].get("required_next_action") or "").strip()
    if not next_action:
        next_action = "Select or synthesize the next bounded independent-resolution candidate, then validate or block with evidence."
    return "; ".join(pieces), source, next_action


def _selector_missing_bounded_fields(payload: dict[str, Any]) -> list[str]:
    if not payload:
        return []

    def has_value(field: str) -> bool:
        value = _selector_field_value(payload, field)
        if isinstance(value, str):
            return bool(value.strip())
        if isinstance(value, list):
            return any(str(item).strip() for item in value)
        return value not in (None, "", [], {})

    required_fields = [
        "selected_task_id",
        "target_file",
        "target_function_or_rule",
        "behavior_delta_one_sentence",
        "validation_command",
        "expected_changed_files",
        "rollback_note",
        "prevention_lesson",
    ]
    return [field for field in required_fields if not has_value(field)]


def _selector_field_completeness_current(payload: dict[str, Any], missing_fields: list[str]) -> tuple[str, str]:
    if not payload:
        return (
            "not published",
            "Run TOD next-task selector and require all bounded selector fields before dispatch.",
        )
    selected_task = str(
        _selector_field_value(payload, "selected_task_id")
        or payload.get("task_id")
        or "unknown"
    ).strip() or "unknown"
    selection_kind = str(
        payload.get("selection_kind")
        or ("candidate_selected" if isinstance(payload.get("selected_candidate_or_none"), dict) else "")
        or "unknown"
    ).strip() or "unknown"
    if not missing_fields:
        return (
            f"complete; selected={selected_task}; selection={selection_kind}; bounded_fields=8/8",
            "Dispatch only after material execution validates changed files, rollback, and prevention evidence.",
        )
    missing_preview = ", ".join(missing_fields)
    return (
        f"incomplete; selected={selected_task}; selection={selection_kind}; missing={missing_preview}; no dispatch credit",
        "TOD must provide selected_task_id, target_file, target_function_or_rule, behavior_delta_one_sentence, validation_command, expected_changed_files, rollback_note, and prevention_lesson before execution or credit.",
    )


def _invalid_partial_selector_current(path: Path | None, payload: dict[str, Any], missing_fields: list[str]) -> tuple[str, str, str]:
    source = path.name if path else "TOD_NEXT_TASK_SELECTION.latest.json"
    selected_task = str(payload.get("selected_task_id") or payload.get("task_id") or "unknown").strip() or "unknown"
    selection_kind = str(payload.get("selection_kind") or "unknown").strip() or "unknown"
    if "packet_formation" in selection_kind:
        dispatch_result = payload.get("dispatch_result") if isinstance(payload.get("dispatch_result"), dict) else {}
        result = dispatch_result.get("result") if isinstance(dispatch_result.get("result"), dict) else {}
        command_output = str(
            result.get("command_output")
            or payload.get("command_output")
            or ""
        ).strip()
        blocker_summary = "packet formation did not produce a behavior-changing code candidate"
        if command_output:
            blocker_summary = " ".join(command_output.split())[:220]
        current = (
            f"packet_formation_blocked_no_credit; selected={selected_task}; selection={selection_kind}; "
            f"{blocker_summary}; no independent-resolution credit"
        )
        next_action = (
            "TOD must choose a different current-code behavior gap and return a behavior-changing selector "
            "with target_file, target_function_or_rule, behavior_delta_one_sentence, validation_command, "
            "expected_changed_files, rollback_note, and prevention_lesson. Packet formation alone remains no-credit."
        )
        return current, source, next_action
    missing_preview = ", ".join(missing_fields[:5])
    if len(missing_fields) > 5:
        missing_preview = f"{missing_preview}, +{len(missing_fields) - 5} more"
    current = (
        f"invalid_partial_selector; selected={selected_task}; selection={selection_kind}; "
        f"missing={missing_preview}; no independent-resolution credit"
    )
    next_action = (
        "TOD must publish a bounded selector with selected_task_id, target_file, target_function_or_rule, "
        "behavior_delta_one_sentence, validation_command, expected_changed_files, rollback_note, and prevention_lesson "
        "before dispatch or independent-resolution credit."
    )
    return current, source, next_action


def _no_viable_candidate_inspection_current(
    payload: dict[str, Any],
    active_execution_result: dict[str, Any] | None = None,
) -> tuple[str, str, str]:
    if not payload:
        return (
            "not published",
            "TOD_NEXT_TASK_SELECTION.latest.json",
            "Run selector and require inspected_files plus blocker.required_next_action when no viable behavior candidate is proven.",
        )
    selection_kind = str(payload.get("selection_kind") or "").strip()
    blocker = payload.get("blocker") if isinstance(payload.get("blocker"), dict) else {}
    inspected_files = payload.get("inspected_files") if isinstance(payload.get("inspected_files"), list) else []
    if not inspected_files and blocker:
        inspected_files = blocker.get("inspected_files") if isinstance(blocker.get("inspected_files"), list) else []
    blocked_reason = str(payload.get("blocked_reason") or blocker.get("reason") or "").strip()
    required_next_action = str(blocker.get("required_next_action") or "").strip()
    if selection_kind != "blocked_no_viable_behavior_candidate":
        return (
            f"not active; latest_selector={selection_kind or 'unknown'}",
            "TOD_NEXT_TASK_SELECTION.latest.json",
            "Monitor the next selector result; require inspected_files only when no viable behavior candidate is active.",
        )
    selector_timestamp = _generated_at_timestamp(payload)
    active_execution_timestamp = _generated_at_timestamp(active_execution_result or {})
    active_execution_status = str(
        (active_execution_result or {}).get("status")
        or (active_execution_result or {}).get("result_status")
        or ""
    ).strip().lower()
    active_execution_is_blocking = active_execution_status in {
        "blocked",
        "blocked_with_inspection",
        "failed",
        "error",
    }
    if (
        active_execution_is_blocking
        and active_execution_timestamp
        and selector_timestamp
        and selector_timestamp < active_execution_timestamp
    ):
        active_reason = str(
            (active_execution_result or {}).get("reason_code")
            or (active_execution_result or {}).get("result_reason_code")
            or ""
        ).strip()
        stale_reason = f"; active_reason={active_reason}" if active_reason else ""
        return (
            f"stale; selector older than latest TOD execution{stale_reason}",
            "TOD_NEXT_TASK_SELECTION.latest.json + TOD_EXECUTION_RESULT.latest.json",
            "Rerun TOD selector for the current execution blocker, then publish selector_ready or no_viable_candidate with inspected files and reason.",
        )
    inspected_preview = ", ".join(str(item).strip() for item in inspected_files[:4] if str(item).strip())
    if len(inspected_files) > 4:
        inspected_preview = f"{inspected_preview}, +{len(inspected_files) - 4} more"
    if not inspected_preview:
        inspected_preview = "missing inspected_files"
    reason_preview = " ".join(blocked_reason.split())[:180] if blocked_reason else "missing blocked_reason"
    current = f"active; inspected={inspected_preview}; reason={reason_preview}"
    next_action = (
        required_next_action
        or "Inspect a different current-code target and materialize a behavior-changing candidate, or keep this blocker active with inspected files and reason."
    )
    return current, "TOD_NEXT_TASK_SELECTION.latest.json", next_action


def _latest_dedupe_guard(root: Path) -> tuple[Path | None, dict[str, Any]]:
    if not root.exists():
        return None, {}
    candidates = sorted(
        root.glob("CODEX_TOD_UI_HANDOFF_DEDUPE_GUARD_*.latest.json"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for path in candidates:
        payload = _load_json(path)
        if payload:
            return path, payload
    return None, {}


def _latest_intervention(root: Path, pattern: str) -> tuple[Path | None, dict[str, Any]]:
    if not root.exists():
        return None, {}
    candidates = sorted(root.glob(pattern), key=lambda path: path.stat().st_mtime, reverse=True)
    for path in candidates:
        payload = _load_json(path)
        if payload:
            return path, payload
    return None, {}


def _tod_tsk3394_material_push_current(payload: dict[str, Any]) -> tuple[str, str]:
    if not payload:
        return (
            "not active",
            "Create a TOD-owned material execution push only when the active blocker has a single target file and validation command.",
        )
    status = str(payload.get("status") or "unknown").strip()
    task_id = str(payload.get("task_id") or "unknown").strip()
    target_file = str(payload.get("target_file") or "unknown").strip()
    codex_patch_supplied = bool(payload.get("codex_patch_supplied"))
    no_credit_outcomes = payload.get("no_credit_outcomes") if isinstance(payload.get("no_credit_outcomes"), list) else []
    no_credit_count = len(no_credit_outcomes)
    current = (
        f"{status}; task={task_id}; target={target_file}; "
        f"codex_patch_supplied={str(codex_patch_supplied).lower()}; "
        f"no_credit_outcomes={no_credit_count}"
    )
    next_action = str(payload.get("required_action") or "").strip() or (
        "TOD must inspect the target file and produce changed files plus validation, or block with inspected evidence."
    )
    return current, next_action


def _tod_autonomous_daemon_health_current(payload: dict[str, Any]) -> tuple[str, str]:
    if not payload:
        return (
            "not checked in current cycle",
            "Run controlled daemon health only when it will not spawn noisy fixture tasks; otherwise keep TOD autonomy pressure on selector evidence.",
        )
    status = str(payload.get("status") or "unknown").strip()
    observed = " ".join(str(payload.get("observed_result") or "").split())
    blocker = " ".join(str(payload.get("current_blocker") or "").split())
    observed_piece = f"; observed={observed[:140]}" if observed else ""
    blocker_piece = f"; blocker={blocker[:120]}" if blocker else ""
    next_action = str(payload.get("next_action") or "").strip() or (
        "Do not count daemon health fixture tasks as TOD progress; require a bounded target file or selector evidence before retrying autonomous execution."
    )
    return f"{status}{observed_piece}{blocker_piece}", next_action


def _tod_materialization_timeout_current(root: Path) -> tuple[str, str, str]:
    if not root.exists():
        return (
            "no bounded materialization timeout recorded",
            "codex_training_interventions",
            "If TOD stays blocked on bounded edit materialization, record no-credit timeout evidence rather than repeating the same nudge.",
        )
    attempts: list[tuple[float, Path, dict[str, Any]]] = []
    timeout_patterns = (
        "CODEX_TOD_BOUNDED_EDIT_MATERIALIZATION_TIMEOUT_*.latest.json",
        "CODEX_TOD_STUDIO_OLD_NEW_PACKET_TIMEOUT_*.latest.json",
        "CODEX_TOD_STUDIO_BRANCH_PATCH_SYNTHESIS_TIMEOUT_*.latest.json",
        "CODEX_TOD_STUDIO_EXACT_BRANCH_OBSERVATION_TIMEOUT_*.latest.json",
    )
    for pattern in timeout_patterns:
        for path in root.glob(pattern):
            payload = _load_json(path)
            if not payload:
                continue
            attempts.append((_generated_at_timestamp(payload) or path.stat().st_mtime, path, payload))
    attempts.sort(key=lambda item: item[0], reverse=True)
    if not attempts:
        return (
            "no bounded materialization timeout recorded",
            "codex_training_interventions",
            "If TOD stays blocked on bounded edit materialization, record no-credit timeout evidence rather than repeating the same nudge.",
        )
    _timestamp, latest_path, latest = attempts[0]
    payload = latest.get("payload") if isinstance(latest.get("payload"), dict) else {}
    observed_state = latest.get("observed_state") if isinstance(latest.get("observed_state"), dict) else {}
    credit_decision = latest.get("credit_decision") if isinstance(latest.get("credit_decision"), dict) else {}
    outcome = str(payload.get("outcome") or latest.get("status") or "unknown").strip()
    if "credit" in payload:
        credit = str(payload.get("credit") or "unknown").strip()
    elif credit_decision:
        any_credit = any(
            bool(credit_decision.get(key))
            for key in ("validated_tod_edit", "meaningful_tod_implementation", "independent_tod_resolution")
        )
        credit = "some" if any_credit else "none"
    else:
        credit = "unknown"
    blocker = str(payload.get("blocker") or latest.get("target_file") or "").strip()
    observed = " ".join(
        str(
            payload.get("observed_response")
            or observed_state.get("dialog_status")
            or observed_state.get("latest_packet_status")
            or ""
        ).split()
    )
    observed_piece = f"; observed={observed[:140]}" if observed else ""
    blocker_piece = f"; blocker={blocker}" if blocker else ""
    current = (
        f"{outcome}; count={len(attempts)}; latest={latest_path.name}; credit={credit}"
        f"{blocker_piece}{observed_piece}"
    )
    next_action = (
        "Do not repeat the same materialization nudge. TOD needs a different capability drill: inspect a target file, "
        "emit target_file plus old_text_or_anchor/new_text_or_snippet, then validate before execution credit."
    )
    return current, latest_path.name, next_action


def _tod_different_target_discovery_current(root: Path) -> tuple[str, str, str]:
    _, latest_selector = _freshest_tod_next_task_selection()
    selector_kind = str(latest_selector.get("selection_kind") or "").strip()
    artifact_path = INDEPENDENT_ATTEMPTS_ROOT / "TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json"
    artifact = _load_json(artifact_path)
    artifact_timestamp = _generated_at_timestamp(artifact)
    path, payload = _latest_intervention(
        root,
        "CODEX_TOD_DIFFERENT_TARGET_DISCOVERY_DRILL_*.latest.json",
    )
    payload_timestamp = _generated_at_timestamp(payload)
    if payload and (not artifact or payload_timestamp >= artifact_timestamp):
        status = str(payload.get("status") or "unknown").strip()
        instruction = payload.get("tod_training_instruction") if isinstance(payload.get("tod_training_instruction"), dict) else {}
        required_artifact = str(instruction.get("required_output_artifact") or "").strip()
        success_condition = " ".join(str(instruction.get("success_condition") or "").split())
        forbidden_paths = instruction.get("forbidden_paths") if isinstance(instruction.get("forbidden_paths"), list) else []
        forbidden_preview = ", ".join(str(item).strip() for item in forbidden_paths[:3] if str(item).strip())
        current_parts = [status]
        if required_artifact:
            current_parts.append(f"requires={required_artifact}")
        if forbidden_preview:
            current_parts.append(f"forbidden={forbidden_preview}")
        if success_condition:
            current_parts.append(f"success={success_condition[:180]}")
        next_action = str(instruction.get("action") or "").strip()
        if not next_action:
            next_action = (
                "TOD must inspect different current-code targets and publish either one fresh behavior-changing candidate "
                "or a no-viable blocker with inspected files and reason."
            )
        return "; ".join(current_parts), path.name if path else "codex_training_interventions", next_action
    if selector_kind == "blocked_no_viable_behavior_candidate":
        inspected_files = latest_selector.get("inspected_files") if isinstance(latest_selector.get("inspected_files"), list) else []
        inspected_preview = ", ".join(str(item).strip() for item in inspected_files[:4] if str(item).strip())
        if len(inspected_files) > 4:
            inspected_preview = f"{inspected_preview}, +{len(inspected_files) - 4} more"
        if not inspected_preview:
            inspected_preview = "selector inspected files not listed"
        blocker = latest_selector.get("blocker") if isinstance(latest_selector.get("blocker"), dict) else {}
        reason = str(
            latest_selector.get("blocked_reason")
            or blocker.get("reason")
            or "newer no-viable selector supersedes stale discovery candidate"
        ).strip()
        current = (
            f"superseded_by_no_viable_selector; inspected={inspected_preview}; "
            f"reason={reason[:180]}"
        )
        next_action = (
            "Do not dispatch older discovery candidates. Repair discovery so it honors forbidden targets and inspects "
            "genuinely different current-code files, or keep the no-viable blocker active with inspected evidence."
        )
        return current, "TOD_NEXT_TASK_SELECTION.latest.json", next_action

    dispatch_path, dispatch = _latest_intervention(
        root,
        "CODEX_TOD_STUDIO_MODE_GUARD_DISPATCH_*.latest.json",
    )
    dispatch_timestamp = _generated_at_timestamp(dispatch)
    if dispatch and (not artifact or dispatch_timestamp > artifact_timestamp):
        status = str(dispatch.get("status") or "unknown").strip()
        evidence = dispatch.get("evidence") if isinstance(dispatch.get("evidence"), dict) else {}
        clean = evidence.get("clean_envelope_dispatch") if isinstance(evidence.get("clean_envelope_dispatch"), dict) else {}
        packet = evidence.get("packet_followup") if isinstance(evidence.get("packet_followup"), dict) else {}
        current_parts = [status]
        clean_task = str(clean.get("task_id") or "").strip()
        clean_status = str(clean.get("status") or "").strip()
        clean_reason = str(clean.get("reason_code") or "").strip()
        required = clean.get("required_clarification") if isinstance(clean.get("required_clarification"), list) else []
        if clean_task:
            current_parts.append(f"task={clean_task}")
        if clean_status:
            current_parts.append(f"implementation={clean_status}")
        if clean_reason:
            current_parts.append(f"reason={clean_reason}")
        if required:
            current_parts.append("missing=" + ", ".join(str(item) for item in required))
        packet_task = str(packet.get("task_id") or "").strip()
        packet_ready = packet.get("packet_candidate_ready")
        if packet_task:
            current_parts.append(f"packet_task={packet_task}")
        if packet_ready is not None:
            current_parts.append(f"packet_ready={str(packet_ready).lower()}")
        next_action = str(dispatch.get("next_action") or "").strip() or (
            "Train TOD candidate materialization to inspect the exact selected target and publish current old_text/new_text or a target-specific blocker."
        )
        return "; ".join(current_parts), dispatch_path.name if dispatch_path else "codex_training_interventions", next_action

    if artifact:
        status = str(artifact.get("status") or "unknown").strip()
        inspected_files = artifact.get("inspected_files") if isinstance(artifact.get("inspected_files"), list) else []
        candidate_count = artifact.get("candidate_count")
        selected = artifact.get("selected_candidate_or_none")
        selected_key = ""
        selected_target = ""
        if isinstance(selected, dict):
            selected_key = str(selected.get("candidate_key") or "").strip()
            selected_target = str(selected.get("target_file") or "").strip()
        elif selected not in (None, "", [], {}):
            selected_key = str(selected).strip()
        _, latest_selector = _freshest_tod_next_task_selection()
        selector_kind = str(latest_selector.get("selection_kind") or "").strip()
        selector_timestamp = _generated_at_timestamp(latest_selector)
        artifact_timestamp = _generated_at_timestamp(artifact)
        if (
            selected_target
            and selector_kind == "blocked_no_viable_behavior_candidate"
            and selector_timestamp
            and artifact_timestamp
            and selector_timestamp >= artifact_timestamp
        ):
            inspected_preview = ", ".join(
                str(item).strip()
                for item in (latest_selector.get("inspected_files") or [])[:4]
                if str(item).strip()
            )
            if not inspected_preview:
                inspected_preview = "selector inspected files not listed"
            blocker = latest_selector.get("blocker") if isinstance(latest_selector.get("blocker"), dict) else {}
            reason = str(
                latest_selector.get("blocked_reason")
                or blocker.get("reason")
                or "newer no-viable selector supersedes stale discovery candidate"
            ).strip()
            current = (
                f"stale_candidate_superseded; previous_selected={selected_key or 'unknown'}; "
                f"previous_target={selected_target}; latest_selector={selector_kind}; "
                f"inspected={inspected_preview}; reason={reason[:160]}"
            )
            next_action = (
                "Do not dispatch the stale discovery candidate. Repair discovery so it honors forbidden targets "
                "and inspects genuinely different current-code files, or keep the no-viable blocker active."
            )
            return current, "TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json + TOD_NEXT_TASK_SELECTION.latest.json", next_action
        credit = artifact.get("credit_decision") if isinstance(artifact.get("credit_decision"), dict) else {}
        credit_reason = str(credit.get("reason") or "").strip()
        current_parts = [
            status,
            f"inspected_files={len(inspected_files)}",
        ]
        if candidate_count not in (None, ""):
            current_parts.append(f"candidate_count={candidate_count}")
        if selected_key:
            current_parts.append(f"selected={selected_key}")
        if selected_target:
            current_parts.append(f"target={selected_target}")
        if credit_reason:
            current_parts.append(f"credit={credit_reason[:140]}")
        blocker = artifact.get("blocker") if isinstance(artifact.get("blocker"), dict) else {}
        if status == "blocked_no_viable_candidate" or not selected_key:
            next_action = str(blocker.get("required_next_action") or "").strip() or (
                "Broaden TOD discovery candidate definitions or inspect a new current-code surface outside the forbidden target set."
            )
        else:
            next_action = (
                "Dispatch the selected candidate only as a separate TOD-owned implementation: inspect target, change live-path behavior, "
                "run validation, then publish evidence before any independent-resolution credit."
            )
        return "; ".join(current_parts), artifact_path.name, next_action

    if not payload:
        return (
            "not active",
            "codex_training_interventions",
            "Create a target-discovery drill only after TOD repeats packet/no-op outcomes and needs to inspect different current-code files before dispatch.",
        )
    status = str(payload.get("status") or "unknown").strip()
    instruction = payload.get("tod_training_instruction") if isinstance(payload.get("tod_training_instruction"), dict) else {}
    required_artifact = str(instruction.get("required_output_artifact") or "").strip()
    success_condition = " ".join(str(instruction.get("success_condition") or "").split())
    forbidden_paths = instruction.get("forbidden_paths") if isinstance(instruction.get("forbidden_paths"), list) else []
    forbidden_preview = ", ".join(str(item).strip() for item in forbidden_paths[:3] if str(item).strip())
    current_parts = [status]
    if required_artifact:
        current_parts.append(f"requires={required_artifact}")
    if forbidden_preview:
        current_parts.append(f"forbidden={forbidden_preview}")
    if success_condition:
        current_parts.append(f"success={success_condition[:180]}")
    next_action = str(instruction.get("action") or "").strip()
    if not next_action:
        next_action = (
            "TOD must inspect different current-code targets and publish either one fresh behavior-changing candidate "
            "or a no-viable blocker with inspected files and reason."
        )
    return "; ".join(current_parts), path.name if path else "codex_training_interventions", next_action


def _latest_materialization_timeout_timestamp(root: Path) -> float:
    if not root.exists():
        return 0.0
    timestamps: list[float] = []
    for path in root.glob("CODEX_TOD_BOUNDED_EDIT_MATERIALIZATION_TIMEOUT_*.latest.json"):
        payload = _load_json(path)
        if not payload:
            continue
        timestamp = _generated_at_timestamp(payload) or path.stat().st_mtime
        if timestamp > 0:
            timestamps.append(timestamp)
    return max(timestamps) if timestamps else 0.0


def _packet_field(payload: dict[str, Any], *names: str) -> str:
    packet = payload.get("packet") if isinstance(payload.get("packet"), dict) else {}
    for name in names:
        value = payload.get(name)
        if value in (None, "", [], {}) and packet:
            value = packet.get(name)
        if isinstance(value, str) and value.strip():
            return value.strip()
        if value not in (None, "", [], {}):
            return str(value).strip()
    return ""


def _selector_field_value(payload: dict[str, Any], field: str) -> Any:
    value = payload.get(field)
    if value not in (None, "", [], {}):
        return value

    selector = payload.get("latest_selector_evidence") if isinstance(payload.get("latest_selector_evidence"), dict) else {}
    value = selector.get(field)
    if value not in (None, "", [], {}):
        return value

    directives = _task_focus_directives(
        str(payload.get("task_focus") or payload.get("selected_task_scope") or "")
    )
    directive_alias_map = {
        "selected_task_id": ("selected task id", "task id"),
        "target_file": ("target file",),
        "target_function_or_rule": ("target function or rule", "target rule", "target function"),
        "behavior_delta_one_sentence": ("behavior delta", "behavior delta one sentence"),
        "validation_command": ("validation command",),
        "expected_changed_files": ("expected changed files", "changed files"),
        "rollback_note": ("rollback note",),
        "prevention_lesson": ("prevention lesson",),
    }
    for alias in directive_alias_map.get(field, ()):
        value = directives.get(alias)
        if value not in (None, "", [], {}):
            if field == "expected_changed_files":
                return [item.strip() for item in str(value).split(",") if item.strip()]
            return value
    if field == "selected_task_id":
        value = payload.get("task_id")
        if value not in (None, "", [], {}):
            return value
    if field == "expected_changed_files":
        target = directives.get("target file")
        if target:
            return [target]
    if field == "target_function_or_rule":
        target = directives.get("target file")
        edit_mode = directives.get("edit mode")
        if target and edit_mode:
            return f"{target} {edit_mode}"
    if field == "behavior_delta_one_sentence":
        old_text = directives.get("old text")
        new_text = directives.get("new text")
        if old_text and new_text:
            return f"Replace {old_text[:80]} with {new_text[:80]}"
    if field == "rollback_note":
        target = directives.get("target file")
        old_text = directives.get("old text")
        if target and old_text:
            return f"Restore {old_text[:120]} in {target}."

    selected = payload.get("selected_candidate_or_none")
    if not isinstance(selected, dict):
        return None

    alias_map = {
        "selected_task_id": "candidate_key",
        "target_file": "target_file",
        "target_function_or_rule": "target_function_or_rule",
        "behavior_delta_one_sentence": "behavior_delta_one_sentence",
        "validation_command": "validation_command",
        "expected_changed_files": "expected_changed_files",
        "rollback_note": "rollback_note",
        "prevention_lesson": "prevention_lesson",
    }
    alias = alias_map.get(field)
    if not alias:
        return None
    value = selected.get(alias)
    return value if value not in (None, "", [], {}) else None


def _task_focus_directives(task_focus: str) -> dict[str, str]:
    directives: dict[str, str] = {}
    current_key = ""
    current_lines: list[str] = []

    def flush() -> None:
        nonlocal current_key, current_lines
        if current_key:
            directives[current_key] = "\n".join(current_lines).strip()
        current_key = ""
        current_lines = []

    for raw_line in task_focus.splitlines():
        line = raw_line.rstrip()
        if ":" in line:
            key, value = line.split(":", 1)
            normalized = key.strip().lower()
            if normalized and len(normalized) <= 40:
                flush()
                current_key = normalized
                current_lines = [value.strip()] if value.strip() else []
                continue
        if current_key:
            current_lines.append(line.strip())
    flush()
    return directives


def _tod_current_code_packet_capability_current(
    attempts_root: Path,
    interventions_root: Path,
) -> tuple[str, str, str]:
    timeout_timestamp = _latest_materialization_timeout_timestamp(interventions_root)
    if not attempts_root.exists():
        return (
            "no packet capability artifacts found",
            "tod_independent_resolution_attempts",
            "Run a packet-formation capability drill that inspects one target file and emits actionable current-code old/new or anchor/snippet fields.",
        )

    attempts: list[tuple[float, Path, dict[str, Any]]] = []
    packet_paths = [
        *attempts_root.glob("TOD_PACKET_FORMATION*.json"),
        *attempts_root.glob("TOD_*BOUNDED_PACKET*.json"),
    ]
    for path in packet_paths:
        payload = _load_json(path)
        if not payload:
            continue
        timestamp = _generated_at_timestamp(payload) or path.stat().st_mtime
        attempts.append((timestamp, path, payload))
    attempts.sort(key=lambda item: item[0], reverse=True)
    if not attempts:
        return (
            "no packet capability artifacts found",
            "tod_independent_resolution_attempts",
            "Run a packet-formation capability drill that inspects one target file and emits actionable current-code old/new or anchor/snippet fields.",
        )

    post_timeout = [item for item in attempts if timeout_timestamp <= 0 or item[0] > timeout_timestamp]
    latest_timestamp, latest_path, latest_payload = (post_timeout or attempts)[0]
    source = latest_path.name
    task_id = _packet_field(latest_payload, "task_id", "selected_task_id")
    status = _packet_field(latest_payload, "status") or "unknown"
    target_file = _packet_field(latest_payload, "target_file")
    edit_mode = _packet_field(latest_payload, "intended_edit_mode", "edit_mode")
    old_text = _packet_field(latest_payload, "old_text", "exact_current_anchor_or_old_text")
    new_text = _packet_field(latest_payload, "new_text", "different_new_text")
    anchor = _packet_field(latest_payload, "anchor", "exact_current_anchor")
    snippet = _packet_field(latest_payload, "snippet", "new_text_or_snippet")
    validation_command = _packet_field(latest_payload, "validation_command")
    prevention_lesson = _packet_field(latest_payload, "prevention_lesson")
    dave_needed = _packet_field(latest_payload, "dave_needed")
    ready = bool(latest_payload.get("packet_candidate_ready"))
    has_current_code_edit = (
        bool(target_file)
        and bool(edit_mode)
        and edit_mode.lower() not in {"validation_only", "pending", "none"}
        and ((bool(old_text) and bool(new_text) and old_text != new_text) or (bool(anchor) and bool(snippet)))
        and bool(validation_command)
        and bool(prevention_lesson)
        and bool(dave_needed)
    )
    if post_timeout and ready and has_current_code_edit:
        current = (
            f"post_timeout_packet_candidate_ready; status={status}; task={task_id or 'unknown'}; "
            f"target={target_file}; edit_mode={edit_mode}; no independent-resolution credit until executed"
        )
        next_action = (
            "Dispatch the packet-derived code task only if old_text or anchor still matches current code, then require changed files, validation, closure evidence, and prevention lesson."
        )
        return current, source, next_action

    blocker = latest_payload.get("blocker") if isinstance(latest_payload.get("blocker"), dict) else {}
    inspected_files = blocker.get("inspected_files") if isinstance(blocker.get("inspected_files"), list) else []
    blocker_target = str(blocker.get("target_file") or target_file or "").strip()
    blocker_reason = " ".join(str(blocker.get("reason") or "").split())
    blocker_next = " ".join(str(blocker.get("required_next_action") or "").split())
    if post_timeout and blocker_target and inspected_files and blocker_next:
        current = (
            f"post_timeout_inspected_packet_blocker; status={status}; task={task_id or 'unknown'}; "
            f"target={blocker_target}; inspected_files={len(inspected_files)}; reason={blocker_reason[:180]}; no execution credit"
        )
        next_action = (
            f"{blocker_next} Then publish either a fresh current-code packet candidate or a no-viable-candidate blocker with inspected files."
        )
        return current, source, next_action

    missing_fields: list[str] = []
    if not target_file:
        missing_fields.append("target_file")
    if not edit_mode or edit_mode.lower() in {"validation_only", "pending", "none"}:
        missing_fields.append("non_validation_edit_mode")
    if not ((old_text and new_text and old_text != new_text) or (anchor and snippet)):
        missing_fields.append("old_text/new_text_or_anchor/snippet")
    if not validation_command:
        missing_fields.append("validation_command")
    if not prevention_lesson:
        missing_fields.append("prevention_lesson")
    if not dave_needed:
        missing_fields.append("dave_needed")
    if not post_timeout and timeout_timestamp > 0:
        current = (
            f"no post-timeout packet capability evidence; latest={source}; latest_status={status}; "
            "latest packet predates materialization timeout"
        )
    else:
        current = (
            f"packet capability incomplete; latest={source}; latest_status={status}; "
            f"missing={', '.join(missing_fields) if missing_fields else 'packet_candidate_ready'}"
        )
    next_action = (
        "TOD must inspect one target file and publish a post-timeout packet with target_file, non-validation edit mode, "
        "current old_text/new_text or anchor/snippet, validation_command, prevention_lesson, and dave_needed."
    )
    return current, source, next_action


def _tod_studio_target_packet_materialization_current(root: Path) -> tuple[str, str, str]:
    path, payload = _latest_intervention(
        root,
        "CODEX_TOD_STUDIO_TARGET_PACKET_MATERIALIZATION_*.latest.json",
    )
    if not payload:
        return (
            "not attempted",
            "codex_training_interventions",
            "Run a target-specific materialization drill for tmp_remote_mim/core/routers/studio.py only if TOD/local has a supported path for producing old_text/new_text or a target-specific blocker.",
        )
    status = str(payload.get("status") or "unknown").strip()
    evidence = payload.get("evidence") if isinstance(payload.get("evidence"), dict) else {}
    requested_target = str(evidence.get("requested_target") or "").strip()
    requested_artifact = str(evidence.get("requested_artifact") or "").strip()
    artifact_exists = evidence.get("artifact_exists")
    run_task = evidence.get("run_task_result") if isinstance(evidence.get("run_task_result"), dict) else {}
    fallback = evidence.get("fallback_packet_result") if isinstance(evidence.get("fallback_packet_result"), dict) else {}
    current_parts = [status]
    if requested_target:
        current_parts.append(f"target={requested_target}")
    if requested_artifact:
        current_parts.append(f"artifact={requested_artifact}")
    if artifact_exists is not None:
        current_parts.append(f"artifact_exists={str(bool(artifact_exists)).lower()}")
    run_reason = str(run_task.get("reason_code") or "").strip()
    if run_reason:
        current_parts.append(f"run_task_reason={run_reason}")
    fallback_target = str(fallback.get("target_file") or "").strip()
    if fallback_target:
        current_parts.append(f"fallback_target={fallback_target}")
    next_action = str(payload.get("next_action") or "").strip() or (
        "Repair TOD candidate materialization so the exact selected target produces current old_text/new_text or a target-specific blocker."
    )
    return "; ".join(current_parts), path.name if path else "codex_training_interventions", next_action


def _tod_recovery_packet_regression_current(root: Path) -> tuple[str, str, str]:
    path, payload = _latest_intervention(
        root,
        "CODEX_TOD_RECOVERY_PACKET_REGRESSION_*.latest.json",
    )
    if not payload:
        return (
            "not detected in current evidence",
            "codex_training_interventions",
            "Keep watching for selector drift from a precise blocker back into generic packet-formation work.",
        )
    status = str(payload.get("status") or "unknown").strip()
    selector = payload.get("selector") if isinstance(payload.get("selector"), dict) else {}
    packet = payload.get("packet") if isinstance(payload.get("packet"), dict) else {}
    blocker = packet.get("blocker") if isinstance(packet.get("blocker"), dict) else {}
    selection_kind = str(selector.get("selection_kind") or "").strip()
    selected_task_id = str(selector.get("selected_task_id") or "").strip()
    packet_status = str(packet.get("status") or "").strip()
    ready = packet.get("packet_candidate_ready")
    target_file = str(blocker.get("target_file") or "").strip()
    reason = " ".join(str(blocker.get("reason") or payload.get("nudge") or "").split())
    current_parts = [status]
    if selection_kind:
        current_parts.append(f"selection={selection_kind}")
    if selected_task_id:
        current_parts.append(f"task={selected_task_id}")
    if packet_status:
        current_parts.append(f"packet_status={packet_status}")
    if ready is not None:
        current_parts.append(f"packet_candidate_ready={str(bool(ready)).lower()}")
    if target_file:
        current_parts.append(f"target={target_file}")
    if reason:
        current_parts.append(reason[:180])
    next_action = str(payload.get("nudge") or "").strip() or (
        "Selector must keep the current precise blocker active instead of dispatching generic packet-formation tasks."
    )
    return "; ".join(current_parts), path.name if path else "codex_training_interventions", next_action


def _no_credit_packet_artifact_for_changed_files(changed_files: list[Any]) -> tuple[Path, dict[str, Any]] | None:
    for raw_path in changed_files:
        rel_path = str(raw_path or "").strip().replace("\\", "/")
        if not rel_path.startswith("runtime_remote_training/tod_independent_resolution_attempts/"):
            continue
        path = ROOT / rel_path
        payload = _load_json(path)
        if not payload:
            continue
        credit = payload.get("credit_decision") if isinstance(payload.get("credit_decision"), dict) else {}
        no_credit = (
            credit.get("independent_tod_resolution") is False
            and credit.get("meaningful_tod_implementation") is False
            and credit.get("validated_tod_edit") is False
        )
        if no_credit:
            return path, payload
    return None


def _no_credit_packet_artifact_for_task_id(task_id: str) -> tuple[Path, dict[str, Any]] | None:
    if not task_id or not INDEPENDENT_ATTEMPTS_ROOT.exists():
        return None
    candidates: list[tuple[float, Path, dict[str, Any]]] = []
    for path in INDEPENDENT_ATTEMPTS_ROOT.glob("*.json"):
        payload = _load_json(path)
        if not payload or str(payload.get("task_id") or "").strip() != task_id:
            continue
        credit = payload.get("credit_decision") if isinstance(payload.get("credit_decision"), dict) else {}
        no_credit = (
            credit.get("independent_tod_resolution") is False
            and credit.get("meaningful_tod_implementation") is False
            and credit.get("validated_tod_edit") is False
        )
        if no_credit:
            candidates.append((_generated_at_timestamp(payload) or path.stat().st_mtime, path, payload))
    candidates.sort(key=lambda item: item[0], reverse=True)
    if not candidates:
        return None
    _timestamp, path, payload = candidates[0]
    return path, payload


def _tod_dialog_inbox_health_current(payload: dict[str, Any]) -> tuple[str, str]:
    if not payload:
        return (
            "not checked in current cycle",
            "Run a TOD dialog inbox health read before diagnosing TOD silence as a capability failure.",
        )
    status = str(payload.get("status") or "unknown").strip()
    problem = " ".join(str(payload.get("problem_identified") or "").split())
    validation = payload.get("validation") if isinstance(payload.get("validation"), dict) else {}
    result = " ".join(str(validation.get("result") or "").split())
    pieces = [status]
    if result:
        pieces.append(result[:140])
    if problem:
        pieces.append(f"problem={problem[:140]}")
    next_action = (
        "Keep dialog inbox reads fast enough for monitoring; if TOD is silent, first verify open_sessions and read latency before sending another nudge."
    )
    return "; ".join(pieces), next_action


def _tod_governed_dialog_consumption_current(payload: dict[str, Any]) -> tuple[str, str]:
    if not payload:
        return (
            "not checked in current cycle",
            "If TOD ignores governed handoffs, inspect whether the autonomous loop consumes MIM-to-TOD read-inbox sessions before sending more prompts.",
        )
    status = str(payload.get("status") or "unknown").strip()
    problem = " ".join(str(payload.get("problem_identified") or "").split())
    evidence = payload.get("evidence") if isinstance(payload.get("evidence"), dict) else {}
    daemon = " ".join(str(evidence.get("daemon_behavior_observed") or "").split())
    current_parts = [status]
    if problem:
        current_parts.append(f"problem={problem[:180]}")
    if daemon:
        current_parts.append(f"daemon={daemon[:160]}")
    next_action = str(payload.get("recommended_next_action") or "").strip() or (
        "Add a TOD-owned governed inbox consumer before sending more MIM-to-TOD patch prompts."
    )
    return "; ".join(current_parts), next_action


def _tod_governed_inbox_consumer_dispatch_current(payload: dict[str, Any]) -> tuple[str, str]:
    if not payload:
        return "", ""
    status = str(payload.get("status") or "unknown").strip()
    evidence = payload.get("evidence") if isinstance(payload.get("evidence"), dict) else {}
    implementation = (
        evidence.get("implementation_task_result")
        if isinstance(evidence.get("implementation_task_result"), dict)
        else {}
    )
    packet = (
        evidence.get("packet_formation_task_result")
        if isinstance(evidence.get("packet_formation_task_result"), dict)
        else {}
    )
    credit = payload.get("credit_decision") if isinstance(payload.get("credit_decision"), dict) else {}
    current_parts = [status]
    impl_status = str(implementation.get("status") or "").strip()
    impl_reason = str(implementation.get("reason_code") or "").strip()
    if impl_status:
        current_parts.append(f"implementation_task={impl_status}")
    if impl_reason:
        current_parts.append(f"reason={impl_reason}")
    packet_status = str(packet.get("status") or "").strip()
    dispatch_status = str(packet.get("dispatch_status") or "").strip()
    if packet_status:
        current_parts.append(f"packet_task={packet_status}")
    if dispatch_status:
        current_parts.append(f"dispatch={dispatch_status}")
    if credit:
        independent_credit = credit.get("independent_tod_resolution")
        current_parts.append(f"independent_credit={str(independent_credit).lower()}")
    next_action = str(payload.get("next_action") or "").strip() or (
        "Give TOD a fresh, single-target behavior gap or improve TOD candidate discovery before another implementation dispatch."
    )
    return "; ".join(current_parts), next_action


def _packet_formation_loop_current(root: Path) -> tuple[str, str, str]:
    if not root.exists():
        return (
            "no packet-formation attempt artifacts",
            "tod_independent_resolution_attempts",
            "Monitor whether TOD selects a behavior-changing candidate or keeps looping on packet formation.",
        )
    attempts: list[tuple[float, Path, dict[str, Any]]] = []
    for path in root.glob("TOD_PACKET_FORMATION*.json"):
        payload = _load_json(path)
        if not payload:
            continue
        credit = payload.get("credit_decision") if isinstance(payload.get("credit_decision"), dict) else {}
        no_credit = credit.get("independent_tod_resolution") is False
        status = str(payload.get("status") or "").strip()
        if no_credit and status in {"blocked_candidate_already_applied", "packet_candidate_ready", "blocked_current_code_anchor_missing"}:
            attempts.append((_generated_at_timestamp(payload) or path.stat().st_mtime, path, payload))
    attempts.sort(key=lambda item: item[0], reverse=True)
    recent = attempts[:3]
    if len(recent) < 2:
        return (
            "not repeated",
            recent[0][1].name if recent else "tod_independent_resolution_attempts",
            "Keep watching for repeated packet-only selections; one no-credit packet blocker is acceptable evidence, repeated packet loops need selector repair.",
        )
    repeated_no_credit = [
        payload for _timestamp, _path, payload in recent if str(payload.get("status") or "") == "blocked_candidate_already_applied"
    ]
    if len(repeated_no_credit) < 2:
        return (
            f"{len(recent)} recent packet-formation attempts; no repeated already-applied loop yet",
            recent[0][1].name,
            "Keep watching for repeated packet-only selections; dispatch only behavior-changing candidates.",
        )
    tasks = [
        str(payload.get("task_id") or payload.get("selected_task_id") or path.stem).strip()
        for _timestamp, path, payload in recent
        if str(payload.get("status") or "") == "blocked_candidate_already_applied"
    ]
    _, latest_selector = _freshest_tod_next_task_selection()
    selector_kind = str(latest_selector.get("selection_kind") or "").strip()
    selector_status = str(latest_selector.get("dispatch_status") or "").strip()
    selector_evidence = " ".join(str(item) for item in latest_selector.get("expected_evidence", []) if item)
    selector_is_packet_guard = (
        selector_kind == "blocked_repeated_packet_formation_no_credit"
        or (
            selector_kind == "blocked_no_viable_behavior_candidate"
            and "packet_formation_terminal_blocker" in selector_evidence
        )
    )
    if selector_is_packet_guard:
        current = (
            f"guard_active_repeated_packet_formation_no_credit; attempts={len(repeated_no_credit)}; "
            f"tasks={', '.join(tasks[:3])}; latest_selector={selector_kind}; dispatch={selector_status or 'unknown'}"
        )
        next_action = (
            "TOD must now choose a different behavior-changing code candidate or publish a no-viable-candidate "
            "blocker with inspected files and reason."
        )
        return current, "TOD_NEXT_TASK_SELECTION.latest.json", next_action
    current = (
        f"repeated_packet_formation_no_credit; attempts={len(repeated_no_credit)}; "
        f"tasks={', '.join(tasks[:3])}; selector is still choosing packet/no-op artifacts instead of a fresh behavior-changing code gap"
    )
    next_action = (
        "Repair or retrain selector preference so repeated packet-formation/no-op outcomes are terminal blockers, "
        "then choose a different behavior-changing code candidate or publish a no-viable-candidate blocker."
    )
    return current, recent[0][1].name, next_action


def _dedupe_guard_current(payload: dict[str, Any]) -> str:
    if not payload:
        return "not published"
    status = str(payload.get("status") or "unknown").strip()
    smoke = payload.get("live_smoke") if isinstance(payload.get("live_smoke"), dict) else {}
    deduped = smoke.get("deduped")
    reason = str(smoke.get("dedupe_reason") or "").strip()
    open_count = smoke.get("open_dialog_count_after")
    session_id = str(smoke.get("reused_session_id") or "").strip()
    pieces = [status]
    if deduped is not None:
        pieces.append(f"live_smoke_deduped={bool(deduped)}")
    if reason:
        pieces.append(f"reason={reason}")
    if open_count is not None:
        pieces.append(f"open_dialog_count_after={open_count}")
    if session_id:
        pieces.append(f"reused={session_id}")
    return "; ".join(pieces)


def _artifact_write_repair_supersedes_candidate(
    candidate_path: Path | None,
    candidate: dict[str, Any],
    practice_path: Path,
    practice: dict[str, Any],
) -> bool:
    if not candidate or not practice:
        return False
    candidate_status = str(candidate.get("status") or "").lower()
    candidate_kind = str(candidate.get("selection_kind") or "").lower()
    if "artifact_write" not in f"{candidate_status} {candidate_kind}":
        return False
    practice_status = str(practice.get("status") or "").lower()
    practice_source = str(practice.get("source") or "").lower()
    if practice_status != "practice_blocked_with_current_code_inspection":
        return False
    if "localexecutionengine.artifact_write" not in practice_source:
        return False
    candidate_ts = _generated_at_timestamp(candidate)
    practice_ts = _generated_at_timestamp(practice)
    if practice_ts <= 0:
        return False
    if candidate_ts > 0:
        return practice_ts >= candidate_ts
    if candidate_path and practice_path.exists():
        return practice_path.stat().st_mtime >= candidate_path.stat().st_mtime
    return True


def _patch_synthesis_practice_current(payload: dict[str, Any]) -> str:
    if not payload:
        return "not started"
    status = str(payload.get("status") or "unknown")
    exercise = str(payload.get("exercise_id") or payload.get("objective_id") or "").strip()
    required = payload.get("required_outputs") if isinstance(payload.get("required_outputs"), list) else []
    if not required:
        required = payload.get("required_output") if isinstance(payload.get("required_output"), list) else []
    pieces = [status]
    if exercise:
        pieces.append(f"exercise={exercise}")
    if required:
        pieces.append(f"required_outputs={len(required)}")
    return "; ".join(pieces)


def _latest_patch_synthesis_practice_backup(root: Path) -> tuple[Path | None, dict[str, Any]]:
    if not root.exists():
        return None, {}
    candidates = sorted(
        root.glob("TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json*"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for path in candidates:
        payload = _load_json(path)
        if payload:
            return path, payload
    return None, {}


def _patch_synthesis_practice_metric(payload: dict[str, Any], backup_path: Path | None, backup_payload: dict[str, Any]) -> str:
    if payload:
        return _patch_synthesis_practice_current(payload)
    if not backup_payload:
        return "not started"
    current = _patch_synthesis_practice_current(backup_payload)
    backup_name = backup_path.name if backup_path else "local-engine-backup"
    return f"current artifact missing; backup evidence={current}; backup={backup_name}"


def _drill_token(text: str) -> str:
    value = str(text or "").strip()
    if not value:
        return ""
    return value.split(":", 1)[0].strip()


def _drill_number(text: str) -> int | None:
    token = _drill_token(text)
    match = re.search(r"DRILL-(\d+)", token)
    if not match:
        return None
    return int(match.group(1))


def _completed_blocker_drills() -> set[str]:
    root = TRAINING_ROOT / "blocked_objective_training"
    completed: set[str] = set()
    if not root.exists():
        return completed
    for path in root.glob("TOD_BLOCKER_RESOLUTION_DRILL_*.latest.json"):
        payload = _load_json(path)
        status = str(payload.get("status") or "").strip().lower()
        drill_id = _drill_token(str(payload.get("drill_id") or path.stem))
        if drill_id and status in {"completed", "completed_with_evidence", "superseded_with_evidence"}:
            completed.add(drill_id)
    return completed


def _latest_completed_blocker_drill() -> tuple[str, str] | None:
    root = TRAINING_ROOT / "blocked_objective_training"
    latest: tuple[int, str, str] | None = None
    if not root.exists():
        return None
    for path in root.glob("TOD_BLOCKER_RESOLUTION_DRILL_*.latest.json"):
        payload = _load_json(path)
        status = str(payload.get("status") or "").strip().lower()
        if status not in {"completed", "completed_with_evidence", "superseded_with_evidence"}:
            continue
        drill_id = _drill_token(str(payload.get("drill_id") or path.stem))
        number = _drill_number(drill_id)
        if not drill_id or number is None:
            continue
        if latest is None or number > latest[0]:
            latest = (number, drill_id, status)
    if latest is None:
        return None
    return latest[1], latest[2]


def _dispatcher_current(payload: dict[str, Any], completed_drills: set[str] | None = None) -> str:
    status = str(payload.get("status") or "unknown")
    last_action = str(payload.get("last_action") or "").strip()
    idle_training = payload.get("idle_training") if isinstance(payload.get("idle_training"), dict) else {}
    blocker_training = idle_training.get("blocked_objective_training") if isinstance(idle_training.get("blocked_objective_training"), dict) else {}
    next_drill = str(blocker_training.get("next_drill") or "").strip()
    pieces = [status]
    if last_action:
        pieces.append(f"last_action={last_action}")
    if next_drill and _drill_token(next_drill) not in (completed_drills or set()):
        pieces.append(f"next={next_drill}")
    return "; ".join(pieces)


def _idle_training_current(payload: dict[str, Any], completed_drills: set[str] | None = None) -> str:
    status = str(payload.get("status") or payload.get("state") or "unknown")
    blocker_training = payload.get("blocked_objective_training") if isinstance(payload.get("blocked_objective_training"), dict) else {}
    current_drill = str(blocker_training.get("current_drill") or "").strip()
    current_status = str(blocker_training.get("current_drill_status") or "").strip()
    next_drill = str(blocker_training.get("next_drill") or "").strip()
    latest_completed = _latest_completed_blocker_drill()
    pieces = [status]
    if latest_completed and current_drill:
        latest_drill, latest_status = latest_completed
        latest_number = _drill_number(latest_drill)
        current_number = _drill_number(current_drill)
        if latest_number is not None and current_number is not None and latest_number > current_number:
            pieces.append(f"current={latest_drill}")
            pieces.append(f"drill_status={latest_status}")
            pieces.append(f"supersedes_stale_current={current_drill}")
        else:
            pieces.append(f"current={current_drill}")
            if current_status:
                pieces.append(f"drill_status={current_status}")
    elif current_drill:
        pieces.append(f"current={current_drill}")
        if current_status:
            pieces.append(f"drill_status={current_status}")
    if current_status and not current_drill and not latest_completed:
        pieces.append(f"drill_status={current_status}")
    if next_drill and _drill_token(next_drill) not in (completed_drills or set()):
        pieces.append(f"next={next_drill}")
    return "; ".join(pieces)


def _coerce_int(value: Any) -> int | None:
    if isinstance(value, dict):
        value = value.get("value")
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _state_proven_independent_resolution_ids(state_path: Path, after_timestamp: float) -> list[str]:
    state = _load_json(state_path)
    tasks = state.get("tasks") if isinstance(state.get("tasks"), list) else []
    proven: list[tuple[float, str]] = []
    excluded_title_markers = ("packet", "artifact_write", "practice", "validation-only")
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
        updated_at = _generated_at_timestamp({"generated_at": task.get("updated_at")})
        if after_timestamp > 0 and updated_at < after_timestamp:
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
        files_changed = [str(item).strip() for item in details.get("files_changed", []) if str(item).strip()] if isinstance(details.get("files_changed"), list) else []
        if not files_changed:
            continue
        proven.append((updated_at, task_id))
    ordered: list[str] = []
    seen: set[str] = set()
    for _timestamp, task_id in sorted(proven, key=lambda item: (item[0], item[1])):
        if task_id in seen:
            continue
        seen.add(task_id)
        ordered.append(task_id)
    return ordered


def _state_proven_validated_edit_ids(state_path: Path, after_timestamp: float) -> list[str]:
    state = _load_json(state_path)
    tasks = state.get("tasks") if isinstance(state.get("tasks"), list) else []
    proven: list[tuple[float, str]] = []
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
        updated_at = _generated_at_timestamp({"generated_at": task.get("updated_at")})
        if after_timestamp > 0 and updated_at < after_timestamp:
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
        files_changed = [
            str(item).strip()
            for item in details.get("files_changed", [])
            if str(item).strip()
        ] if isinstance(details.get("files_changed"), list) else []
        if not files_changed:
            continue
        proven.append((updated_at, task_id))
    ordered: list[str] = []
    seen: set[str] = set()
    for _timestamp, task_id in sorted(proven, key=lambda item: (item[0], item[1])):
        if task_id in seen:
            continue
        seen.add(task_id)
        ordered.append(task_id)
    return ordered


def _dialog_sessions_with_latest(path: Path) -> list[dict[str, Any]]:
    payload = _load_json(path)
    raw_sessions = payload.get("sessions") if isinstance(payload.get("sessions"), list) else []
    sessions_by_id: dict[str, dict[str, Any]] = {}
    indexed_session_ids: set[str] = set()
    for raw_session in raw_sessions:
        if not isinstance(raw_session, dict):
            continue
        session = dict(raw_session)
        session_path_raw = str(session.get("session_path") or "").strip()
        if session_path_raw:
            latest_state_path = Path(session_path_raw.replace(".jsonl", ".latest.json"))
            latest_state = _load_json(latest_state_path)
            session_path = Path(session_path_raw)
            is_local_missing_session = (
                not latest_state
                and not session_path.exists()
                and (
                    session_path.is_absolute()
                    or str(session_path_raw).startswith(str(path.parent))
                )
            )
            if is_local_missing_session:
                continue
            session_status = str(session.get("status") or "").strip().lower()
            latest_status = str(latest_state.get("status") or "").strip().lower() if latest_state else ""
            if (
                latest_state
                and _state_timestamp(latest_state) >= _state_timestamp(session)
                and not (session_status in {"closed", "resolved"} and latest_status not in {"closed", "resolved"})
            ):
                session = {**session, **latest_state}
            if _session_has_reply_after_open(session, session_path):
                session = {
                    **session,
                    "status": "closed",
                    "closure_reason": "session_log_reply_after_open",
                }
        session_id = str(session.get("session_id") or session_path_raw or "").strip()
        if session_id:
            indexed_session_ids.add(session_id)
            sessions_by_id[session_id] = session
    dialog_dir = path.parent
    if dialog_dir.exists():
        for latest_state_path in dialog_dir.glob("MIM_TOD_DIALOG.session-*.latest.json"):
            latest_state = _load_json(latest_state_path)
            if not latest_state:
                continue
            session_id = str(latest_state.get("session_id") or latest_state_path.stem).strip()
            if not session_id:
                continue
            if indexed_session_ids and session_id not in indexed_session_ids:
                latest_status = str(latest_state.get("status") or "").strip().lower()
                if latest_status not in {"awaiting_reply", "timed_out", "open"}:
                    continue
                latest_age_hours = (
                    datetime.now(timezone.utc).timestamp() - _state_timestamp(latest_state)
                ) / 3600
                if latest_age_hours > 24:
                    continue
            previous = sessions_by_id.get(session_id, {})
            previous_status = str(previous.get("status") or "").strip().lower()
            latest_status = str(latest_state.get("status") or "").strip().lower()
            if previous_status in {"closed", "resolved"} and latest_status not in {"closed", "resolved"}:
                continue
            if latest_status in {"closed", "resolved"}:
                sessions_by_id[session_id] = {**previous, **latest_state}
                continue
            latest_session_path_raw = str(latest_state.get("session_path") or "").strip()
            if latest_session_path_raw and _session_has_reply_after_open(latest_state, Path(latest_session_path_raw)):
                latest_state = {
                    **latest_state,
                    "status": "closed",
                    "closure_reason": "session_log_reply_after_open",
                }
            if _state_timestamp(latest_state) >= _state_timestamp(previous):
                sessions_by_id[session_id] = {**previous, **latest_state}
    return list(sessions_by_id.values())


def _dialog_index_open_summary(path: Path) -> dict[str, Any]:
    payload = _load_json(path)
    raw_sessions = payload.get("sessions") if isinstance(payload.get("sessions"), list) else []
    summary: dict[str, Any] = {
        "raw_open": 0,
        "open_to_mim": 0,
        "open_to_tod": 0,
        "open_to_other": 0,
        "missing_session_files": 0,
        "local_session_files": 0,
    }
    for raw_session in raw_sessions:
        if not isinstance(raw_session, dict):
            continue
        status = str(raw_session.get("status") or "").strip().lower()
        if status not in {"awaiting_reply", "timed_out", "open"}:
            continue
        open_reply = raw_session.get("open_reply") if isinstance(raw_session.get("open_reply"), dict) else {}
        if not open_reply:
            continue
        summary["raw_open"] += 1
        actor_to = str(open_reply.get("to") or "").strip().upper()
        if actor_to == "MIM":
            summary["open_to_mim"] += 1
        elif actor_to == "TOD":
            summary["open_to_tod"] += 1
        else:
            summary["open_to_other"] += 1

        session_path_raw = str(raw_session.get("session_path") or "").strip()
        session_id = str(raw_session.get("session_id") or "").strip()
        candidates: list[Path] = []
        if session_path_raw:
            session_path = Path(session_path_raw)
            candidates.append(session_path)
            candidates.append(Path(session_path_raw.replace(".jsonl", ".latest.json")))
        if session_id:
            candidates.append(path.parent / f"MIM_TOD_DIALOG.session-{session_id}.jsonl")
            candidates.append(path.parent / f"MIM_TOD_DIALOG.session-{session_id}.latest.json")
        if any(candidate.exists() for candidate in candidates):
            summary["local_session_files"] += 1
        else:
            summary["missing_session_files"] += 1
    return summary


def _open_reply_with_session_payload(session: dict[str, Any]) -> dict[str, Any]:
    open_reply = session.get("open_reply") if isinstance(session.get("open_reply"), dict) else {}
    last_message = session.get("last_message") if isinstance(session.get("last_message"), dict) else {}
    if not open_reply and last_message:
        open_reply = dict(last_message)
    session_path_raw = str(session.get("session_path") or "").strip()
    session_path = Path(session_path_raw) if session_path_raw else None
    if not (session_path and session_path.exists()):
        return open_reply
    try:
        correction_payload: dict[str, Any] = {}
        for line in session_path.read_text(encoding="utf-8-sig").splitlines():
            if not line.strip():
                continue
            message = json.loads(line)
            if not isinstance(message, dict):
                continue
            same_route = (
                str(message.get("from") or "").strip() == str(open_reply.get("from") or last_message.get("from") or "").strip()
                and str(message.get("to") or "").strip() == str(open_reply.get("to") or last_message.get("to") or "").strip()
            )
            message_payload = message.get("payload") if isinstance(message.get("payload"), dict) else {}
            if same_route and message_payload:
                correction_payload = message_payload
            if (
                same_route
                and str(message.get("timestamp") or "").strip() == str(open_reply.get("timestamp") or session.get("updated_at") or "").strip()
            ):
                open_reply = {**message, **open_reply}
        if correction_payload:
            existing_payload = open_reply.get("payload") if isinstance(open_reply.get("payload"), dict) else {}
            open_reply["payload"] = {**existing_payload, **correction_payload}
    except Exception:
        pass
    return open_reply


def _local_mirror_only_dialog_session_ids() -> set[str]:
    _, delivery_repair = _latest_intervention(
        CODEX_TRAINING_INTERVENTIONS_ROOT,
        "CODEX_MIM_TOD_DIALOG_DELIVERY_EXISTING_TRANSPORT_REPAIR_*.latest.json",
    )
    current_nudge = delivery_repair.get("current_training_nudge") if isinstance(delivery_repair, dict) else {}
    if not isinstance(current_nudge, dict):
        return set()
    if str(current_nudge.get("delivery") or "").strip().lower() != "local_mirror_only":
        return set()
    session_id = str(current_nudge.get("session_id") or "").strip()
    if not session_id:
        return set()
    session_ids = {session_id}
    if session_id.endswith("-valid"):
        session_ids.add(session_id[: -len("-valid")])
    return session_ids


def _open_dialog_debt_current(path: Path) -> str:
    index_open_summary = _dialog_index_open_summary(path)
    sessions = _dialog_sessions_with_latest(path)
    local_mirror_only_session_ids = _local_mirror_only_dialog_session_ids()
    local_mirror_only_count = 0
    open_sessions: list[dict[str, Any]] = []
    for session in sessions:
        status = str(session.get("status") or "").strip().lower()
        if status not in {"awaiting_reply", "timed_out"}:
            continue
        if not isinstance(session.get("open_reply"), dict) and not isinstance(session.get("last_message"), dict):
            continue
        if str(session.get("session_id") or "").strip() in local_mirror_only_session_ids:
            local_mirror_only_count += 1
            continue
        open_sessions.append(session)
    if not open_sessions:
        raw_open = int(index_open_summary.get("raw_open") or 0)
        if raw_open:
            if (
                int(index_open_summary.get("missing_session_files") or 0) == 0
                and int(index_open_summary.get("local_session_files") or 0) >= raw_open
            ):
                return "0 open replies"
            local_piece = (
                f"local_mirror_only_undelivered={local_mirror_only_count}; "
                if local_mirror_only_count
                else ""
            )
            return (
                f"0 locally materialized unmanaged open replies; {local_piece}"
                f"remote_index_open={raw_open}; "
                f"remote_index_open_to_mim={int(index_open_summary.get('open_to_mim') or 0)}; "
                f"remote_index_open_to_tod={int(index_open_summary.get('open_to_tod') or 0)}; "
                f"remote_index_missing_session_files={int(index_open_summary.get('missing_session_files') or 0)}; "
                f"remote_index_local_session_files={int(index_open_summary.get('local_session_files') or 0)}; "
                "remote_index_source_divergence=yes; existing channel delivery/index reconciliation required"
            )
        if local_mirror_only_count:
            return (
                "0 open replies; "
                f"local_mirror_only_undelivered={local_mirror_only_count}; "
                "remote_inbox_debt=no; existing channel delivery evidence required"
            )
        return "0 open replies"
    governed_open_count = 0
    governed_oldest_age_minutes: float | None = None
    governed_oldest_aging_rule = ""
    governed_overdue_count = 0
    governed_oldest_overdue_minutes: float | None = None
    unmanaged_open_sessions: list[dict[str, Any]] = []
    for session in open_sessions:
        open_reply = _open_reply_with_session_payload(session)
        last_message = session.get("last_message") if isinstance(session.get("last_message"), dict) else {}
        payload = open_reply.get("payload") if isinstance(open_reply.get("payload"), dict) else {}
        actor_from = str(open_reply.get("from") or last_message.get("from") or "").strip()
        actor_to = str(open_reply.get("to") or last_message.get("to") or "").strip()
        dave_needed = str(payload.get("dave_needed") or open_reply.get("dave_needed") or "").strip().lower()
        evidence_required = payload.get("evidence_required") if isinstance(payload.get("evidence_required"), list) else []
        current_evidence = payload.get("current_evidence") if isinstance(payload.get("current_evidence"), list) else []
        requested_reply = payload.get("requested_reply") if isinstance(payload.get("requested_reply"), dict) else {}
        evidence_request = str(payload.get("evidence_request") or "").strip()
        evidence_to_publish = str(payload.get("evidence_to_publish") or "").strip()
        required_fields = payload.get("required_fields") if isinstance(payload.get("required_fields"), list) else []
        required_mim_response_fields = (
            payload.get("required_mim_response_fields")
            if isinstance(payload.get("required_mim_response_fields"), list)
            else []
        )
        required_outputs = payload.get("required_outputs") if isinstance(payload.get("required_outputs"), dict) else {}
        acceptance = payload.get("acceptance") if isinstance(payload.get("acceptance"), list) else []
        no_credit_if = payload.get("no_credit_if") if isinstance(payload.get("no_credit_if"), list) else []
        required_tod_action = str(payload.get("required_tod_action") or "").strip()
        requested_mim_action = str(payload.get("requested_mim_action") or "").strip()
        acceptable_result = str(payload.get("acceptable_result") or "").strip()
        action = str(payload.get("action") or open_reply.get("action") or "").strip()
        requested_action = str(payload.get("requested_action") or "").strip()
        accepted_outcomes = payload.get("accepted_outcomes") if isinstance(payload.get("accepted_outcomes"), list) else []
        explicit_aging_rule = str(payload.get("aging_rule") or "").strip()
        timestamp = str(open_reply.get("timestamp") or session.get("updated_at") or "").strip()
        age_hours: float | None = None
        try:
            parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            age_hours = max(0.0, (datetime.now(timezone.utc) - parsed).total_seconds() / 3600)
        except ValueError:
            age_hours = None
        has_owner = bool(actor_to)
        has_evidence_request = (
            bool(evidence_required)
            or bool(current_evidence)
            or bool(requested_reply.get("needed"))
            or bool(accepted_outcomes)
            or bool(evidence_request)
            or bool(evidence_to_publish)
            or bool(required_fields)
            or bool(required_mim_response_fields)
            or bool(required_outputs)
            or bool(acceptance)
            or bool(no_credit_if)
            or bool(required_tod_action)
            or bool(requested_mim_action)
            or bool(acceptable_result)
            or "evidence" in action.lower()
            or "required fields" in requested_action.lower()
            or "return exactly one selector artifact" in requested_action.lower()
        )
        has_aging_rule = (
            bool(explicit_aging_rule)
            or bool(requested_reply.get("needed"))
            or bool(required_outputs)
            or (age_hours is not None and age_hours < 24)
        )
        internal_route_without_dave_request = (
            not dave_needed
            and bool(requested_reply.get("needed"))
            and actor_from.upper() in {"MIM", "TOD", "CODEX"}
            and actor_to.upper() in {"MIM", "TOD"}
        )
        if has_owner and has_evidence_request and has_aging_rule and (_dave_needed_is_no(dave_needed) or internal_route_without_dave_request):
            governed_open_count += 1
            if age_hours is not None:
                age_minutes = age_hours * 60
                aging_limit_minutes = _aging_rule_minutes(explicit_aging_rule)
                if (
                    aging_limit_minutes is not None
                    and age_minutes >= aging_limit_minutes
                    and "classify responder silence" in explicit_aging_rule.lower()
                ):
                    governed_overdue_count += 1
                    overdue_minutes = age_minutes - aging_limit_minutes
                    if governed_oldest_overdue_minutes is None or overdue_minutes > governed_oldest_overdue_minutes:
                        governed_oldest_overdue_minutes = overdue_minutes
                if governed_oldest_age_minutes is None or age_minutes > governed_oldest_age_minutes:
                    governed_oldest_age_minutes = age_minutes
                    if (
                        "30 minute" in explicit_aging_rule.lower()
                        or "30-minute" in explicit_aging_rule.lower()
                        or "30 minutes" in explicit_aging_rule.lower()
                    ):
                        governed_oldest_aging_rule = "30m"
                    else:
                        governed_oldest_aging_rule = ""
        else:
            unmanaged_open_sessions.append(session)
    if not unmanaged_open_sessions and governed_open_count:
        age_piece = ""
        if governed_oldest_age_minutes is not None:
            age_piece = f"; governed_oldest_age_m={governed_oldest_age_minutes:.1f}"
        rule_piece = f"; governed_oldest_aging_rule={governed_oldest_aging_rule}" if governed_oldest_aging_rule else ""
        if governed_oldest_aging_rule:
            rule_piece = f"; governed_aging_rule={governed_oldest_aging_rule}{rule_piece}"
        overdue_piece = ""
        if governed_overdue_count:
            overdue_piece = f"; governed_overdue={governed_overdue_count}"
            if governed_oldest_overdue_minutes is not None:
                overdue_piece += f"; governed_oldest_overdue_m={governed_oldest_overdue_minutes:.1f}"
        return (
            f"0 unmanaged open replies; {governed_open_count} governed open replies; "
            f"owner_labeled=yes; evidence_required=yes; aging_rule=under_24h{rule_piece}{age_piece}{overdue_piece}; Dave needed=no"
        )
    def open_reply_timestamp(item: dict[str, Any]) -> str:
        open_reply = item.get("open_reply") if isinstance(item.get("open_reply"), dict) else {}
        return str(open_reply.get("timestamp") or item.get("updated_at") or "")

    unmanaged_open_sessions.sort(key=open_reply_timestamp)
    oldest = unmanaged_open_sessions[0]
    newest = unmanaged_open_sessions[-1]
    oldest_id = str(oldest.get("session_id") or "unknown")
    newest_id = str(newest.get("session_id") or "unknown")
    now = datetime.now(timezone.utc)
    old_24h_count = 0
    oldest_age_hours: float | None = None
    for item in unmanaged_open_sessions:
        open_reply = item.get("open_reply") if isinstance(item.get("open_reply"), dict) else {}
        updated_at = str(open_reply.get("timestamp") or item.get("updated_at") or "").strip()
        try:
            parsed = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        age_hours = max(0.0, (now - parsed).total_seconds() / 3600)
        if oldest_age_hours is None or age_hours > oldest_age_hours:
            oldest_age_hours = age_hours
        if age_hours >= 24:
            old_24h_count += 1
    timed_out_count = sum(
        1
        for item in unmanaged_open_sessions
        if bool(item.get("timed_out")) or str(item.get("status") or "").strip().lower() == "timed_out"
    )
    route_counts: dict[str, int] = {}
    for item in unmanaged_open_sessions:
        open_reply = item.get("open_reply") if isinstance(item.get("open_reply"), dict) else {}
        last_message = item.get("last_message") if isinstance(item.get("last_message"), dict) else {}
        actor_from = str(open_reply.get("from") or last_message.get("from") or "unknown").strip() or "unknown"
        actor_to = str(open_reply.get("to") or last_message.get("to") or "unknown").strip() or "unknown"
        route = f"{actor_from}->{actor_to}"
        route_counts[route] = route_counts.get(route, 0) + 1
    routes = ", ".join(f"{route}:{count}" for route, count in sorted(route_counts.items()))
    age_piece = f"older_than_24h={old_24h_count}"
    if oldest_age_hours is not None:
        age_piece = f"{age_piece}; oldest_age_h={oldest_age_hours:.1f}"
    has_last_message_only_unmanaged = any(
        not isinstance(item.get("open_reply"), dict) and isinstance(item.get("last_message"), dict)
        for item in unmanaged_open_sessions
    )
    if governed_open_count or has_last_message_only_unmanaged:
        return (
            f"{len(unmanaged_open_sessions)} unmanaged open replies; governed_open={governed_open_count}; "
            f"timed_out={timed_out_count}; {age_piece}; routes={routes}; "
            f"oldest={oldest_id}; newest={newest_id}"
        )
    return (
        f"{len(unmanaged_open_sessions)} open replies; "
        f"timed_out={timed_out_count}; {age_piece}; routes={routes}; "
        f"oldest={oldest_id}; newest={newest_id}"
    )


def _open_dialog_debt_next_action(current: str) -> str:
    governed_match = re.search(r"governed_open=(\d+)", current)
    if not governed_match:
        governed_match = re.search(r"(\d+)\s+governed open replies", current)
    governed_count = int(governed_match.group(1)) if governed_match else 0
    if "remote_index_source_divergence=yes" in current:
        return (
            "Do not create a new channel or another nudge. Reconcile the existing dialog index against materialized "
            f"session files, then either verify MIM has acknowledged the open indexed requests or close stale index entries "
            f"with evidence. Current debt: {current}"
        )
    if current.startswith("0 open replies") or (
        current.startswith("0 unmanaged open replies") and governed_count <= 0
    ):
        if "local_mirror_only_undelivered=" in current:
            return (
                "Do not create a new channel or new nudge. Verify the existing dialog delivery path, then either deliver "
                f"the local mirror session through the existing channel or close it as undelivered evidence. Current debt: {current}"
            )
        return "No open dialog debt; keep monitoring new owner requests."
    if current.startswith("0 unmanaged open replies") and "governed_overdue=" in current:
        return (
            "Governed open reply has exceeded its own aging rule; classify responder silence, request a precise blocker, "
            f"or close with evidence before starting new training work. Current debt: {current}"
        )
    if current.startswith("0 unmanaged open replies") and governed_count > 0:
        return (
            "Governed open replies are acceptable while owner, evidence, aging, and Dave-needed fields remain valid; "
            f"monitor until reply or aging threshold. Current debt: {current}"
        )
    return (
        "Close, owner-label, or evidence-age the oldest open dialog before creating new training work; "
        f"current debt: {current}"
    )


def _tod_selection_blocker_current(blocker: dict[str, Any]) -> str:
    if not blocker:
        return "no active selection blocker artifact"
    status = str(blocker.get("status") or "unknown").strip()
    blocker_type = str(blocker.get("blocker_type") or "unknown").strip()
    objective_id = str(blocker.get("objective_id") or "unknown").strip()
    session_id = str(blocker.get("active_dialog_session") or "unknown").strip()
    session_state = _load_json(DIALOG_SESSIONS_PATH.parent / f"MIM_TOD_DIALOG.session-{session_id}.latest.json")
    session_status = str(session_state.get("status") or "unknown").strip()
    last_message = session_state.get("last_message") if isinstance(session_state.get("last_message"), dict) else {}
    last_summary = str(last_message.get("summary") or "").strip()
    closed_without_required_evidence = (
        session_status in {"closed", "resolved"}
        and "explicit resolution notice" in last_summary.lower()
    )
    dave_needed = str(blocker.get("dave_needed") or "unknown").strip()
    required = blocker.get("required_next_evidence") if isinstance(blocker.get("required_next_evidence"), list) else []
    required_preview = ", ".join(str(item).strip() for item in required[:4] if str(item).strip())
    if len(required) > 4:
        required_preview = f"{required_preview}, +{len(required) - 4} more"
    if required_preview:
        required_preview = f"; required={required_preview}"
    session_piece = f"; dialog_status={session_status}"
    if closed_without_required_evidence:
        session_piece = f"{session_piece}; closed_without_required_selection_evidence=yes"
    return (
        f"{status}; type={blocker_type}; objective={objective_id}; "
        f"dialog={session_id}{session_piece}; Dave needed={dave_needed}{required_preview}"
    )


def _tod_selection_blocker_next_action(blocker: dict[str, Any]) -> str:
    if not blocker:
        return "No active selection blocker artifact; keep monitoring TOD autonomous resolution evidence."
    aging_rule = str(blocker.get("aging_rule") or "").strip()
    owner = str(blocker.get("owner") or "TOD owns selection evidence; MIM owns dispatch gating.").strip()
    next_action = (
        "TOD must return one smaller code task with selected_task_id, target_file, "
        "target_function_or_rule, behavior_delta_one_sentence, validation_command, "
        "expected_changed_files, rollback_note, and prevention_lesson before another implementation dispatch."
    )
    session_id = str(blocker.get("active_dialog_session") or "").strip()
    session_state = _load_json(DIALOG_SESSIONS_PATH.parent / f"MIM_TOD_DIALOG.session-{session_id}.latest.json") if session_id else {}
    session_status = str(session_state.get("status") or "").strip().lower()
    last_message = session_state.get("last_message") if isinstance(session_state.get("last_message"), dict) else {}
    last_summary = str(last_message.get("summary") or "").strip().lower()
    if session_status in {"closed", "resolved"} and "explicit resolution notice" in last_summary:
        next_action = (
            "TOD closed the smaller-task selection dialog without the required selected_task_id, target_file, "
            "target_function_or_rule, validation_command, rollback_note, and prevention_lesson. Reopen or issue a "
            "new selection nudge, and keep implementation/independent-resolution credit blocked until those fields exist."
        )
    if aging_rule:
        return f"{next_action} Owner: {owner} Aging: {aging_rule}"
    return f"{next_action} Owner: {owner}"


def _selector_supersedes_dialog_blocker(
    blocker: dict[str, Any],
    selector: dict[str, Any],
) -> bool:
    if not blocker or not selector:
        return False
    selector_kind = str(selector.get("selection_kind") or "").strip()
    dispatch_status = str(selector.get("dispatch_status") or "").strip().lower()
    selector_is_complete_candidate = (
        dispatch_status in {"completed", "dispatching", "selected_for_dispatch"}
        and not _selector_missing_bounded_fields(selector)
    )
    if selector_kind != "blocked_no_viable_behavior_candidate" and not selector_is_complete_candidate:
        return False
    selector_ts = _generated_at_timestamp(selector)
    blocker_ts = _generated_at_timestamp(blocker)
    if selector_ts is None:
        return False
    if blocker_ts is None:
        return True
    return selector_ts >= blocker_ts


def _selection_blocker_from_selector(
    selector: dict[str, Any],
) -> tuple[str, str, str]:
    blocker = selector.get("blocker") if isinstance(selector.get("blocker"), dict) else {}
    inspected_files = selector.get("inspected_files") if isinstance(selector.get("inspected_files"), list) else []
    if not inspected_files and isinstance(blocker.get("inspected_files"), list):
        inspected_files = blocker.get("inspected_files")
    inspected_preview = ", ".join(str(item).strip() for item in inspected_files[:4] if str(item).strip())
    if len(inspected_files) > 4:
        inspected_preview = f"{inspected_preview}, +{len(inspected_files) - 4} more"
    if not inspected_preview:
        inspected_preview = "missing inspected_files"
    reason = str(selector.get("blocked_reason") or blocker.get("reason") or "").strip()
    reason_preview = " ".join(reason.split())[:180] if reason else "missing blocked_reason"
    dispatch_status = str(selector.get("dispatch_status") or "unknown").strip() or "unknown"
    current = (
        "selector_blocked_no_viable_behavior_candidate; "
        f"dispatch={dispatch_status}; inspected={inspected_preview}; "
        f"reason={reason_preview}; no independent-resolution credit"
    )
    next_action = str(blocker.get("required_next_action") or "").strip()
    if not next_action:
        next_action = (
            "Inspect a different current-code target and materialize a behavior-changing candidate, "
            "or keep this no-viable blocker active with inspected files and reason."
        )
    return current, "TOD_NEXT_TASK_SELECTION.latest.json", next_action


def _active_owner_requests_current(path: Path) -> str:
    sessions = _dialog_sessions_with_latest(path)
    active: list[dict[str, Any]] = []
    now = datetime.now(timezone.utc)
    for session in sessions:
        if str(session.get("status") or "").strip().lower() != "awaiting_reply":
            continue
        open_reply = session.get("open_reply") if isinstance(session.get("open_reply"), dict) else {}
        if str(open_reply.get("from") or "").strip().upper() != "CODEX":
            continue
        active.append(session)
    if not active:
        return "0 active Codex owner requests"
    active.sort(key=lambda item: str(item.get("updated_at") or ""), reverse=True)
    details: list[str] = []
    for session in active[:3]:
        open_reply = _open_reply_with_session_payload(session)
        last_message = session.get("last_message") if isinstance(session.get("last_message"), dict) else {}
        payload = open_reply.get("payload") if isinstance(open_reply.get("payload"), dict) else {}
        route = f"{open_reply.get('from') or last_message.get('from') or 'unknown'}->{open_reply.get('to') or last_message.get('to') or 'unknown'}"
        session_id = str(session.get("session_id") or "unknown")
        task_id = str(last_message.get("task_id") or "").strip()
        explicit_aging_rule = str(payload.get("aging_rule") or "").strip()
        updated_at = str(open_reply.get("timestamp") or session.get("updated_at") or "").strip()
        age_text = "age_h=unknown"
        try:
            parsed = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            age_text = f"age_h={max(0.0, (now - parsed).total_seconds() / 3600):.1f}"
        except ValueError:
            pass
        pieces = [route, session_id, age_text]
        if task_id:
            pieces.append(f"task={task_id}")
        if (
            "30 minute" in explicit_aging_rule.lower()
            or "30-minute" in explicit_aging_rule.lower()
            or "30 minutes" in explicit_aging_rule.lower()
        ):
            pieces.append("aging=30m")
        details.append(" ".join(pieces))
    suffix = "; ".join(details)
    if len(active) > 3:
        suffix = f"{suffix}; +{len(active) - 3} more"
    return f"{len(active)} active Codex owner request(s): {suffix}"


def _tod_active_request_alignment_current(task_request: dict[str, Any], execution_result: dict[str, Any]) -> str:
    request_id = str(task_request.get("request_id") or task_request.get("task_id") or "").strip()
    request_task_id = str(task_request.get("task_id") or request_id).strip()
    request_status = str(task_request.get("status") or task_request.get("request_status") or "unknown").strip()
    request_target = str(task_request.get("target") or task_request.get("target_executor") or "").strip()
    execution_task_id = str(execution_result.get("task_id") or execution_result.get("request_id") or "").strip()
    execution_status = str(
        execution_result.get("status") or execution_result.get("execution_state") or "unknown"
    ).strip()
    execution_summary = str(execution_result.get("summary") or "").strip()
    request_generated_at = _generated_at_timestamp(task_request)
    execution_generated_at = _generated_at_timestamp(execution_result)
    review_gate = execution_result.get("review_gate") if isinstance(execution_result.get("review_gate"), dict) else {}
    review_gate_passed = review_gate.get("passed")
    reconciliation = (
        execution_result.get("reconciliation") if isinstance(execution_result.get("reconciliation"), dict) else {}
    )
    reconciliation_review_current = reconciliation.get("review_decision_current")
    reconciliation_review_passed = reconciliation.get("review_passed")
    outcome = (
        execution_result.get("execution_outcome")
        if isinstance(execution_result.get("execution_outcome"), dict)
        else {}
    )
    wrapper_ok = outcome.get("ok")

    if not request_id:
        return "no active TOD task request"
    if request_target and request_target.upper() != "TOD":
        return f"latest request {request_id} targets {request_target}; not a TOD execution lane"
    if not execution_task_id:
        return f"pending TOD request {request_id}; no latest TOD execution result"
    if execution_task_id in {request_id, request_task_id}:
        task_piece = f"; task={request_task_id}" if request_task_id and request_task_id != request_id else ""
        caveats: list[str] = []
        if execution_status.lower() == "succeeded" and review_gate_passed is False:
            caveats.append("review_gate=failed")
        if reconciliation_review_current is False:
            caveats.append("review_decision_current=false")
        if reconciliation_review_passed is False:
            caveats.append("review_passed=false")
        if execution_status.lower() == "succeeded" and wrapper_ok is True and caveats:
            caveats.append("wrapper_success_not_material_completion")
        caveat_piece = f"; {'; '.join(caveats)}" if caveats else ""
        return f"aligned; request={request_id}{task_piece}; execution_status={execution_status}{caveat_piece}"
    if request_generated_at and execution_generated_at and execution_generated_at < request_generated_at:
        return (
            f"pending TOD request {request_id}; latest_execution={execution_task_id}; "
            f"latest_execution_status={execution_status}; latest execution is older than current request"
        )
    summary_piece = f"; latest_summary={execution_summary[:120]}" if execution_summary else ""
    return (
        f"mismatch; pending_request={request_id}; request_status={request_status}; "
        f"latest_execution={execution_task_id}; execution_status={execution_status}{summary_piece}"
    )


def _mim_tod_request_shape_current(task_request: dict[str, Any]) -> tuple[str, str, bool]:
    if not task_request:
        return (
            "missing; no live MIM_TOD_TASK_REQUEST payload",
            "MIM must publish one current TOD request before TOD can select, execute, or block with evidence.",
            True,
        )
    request_id = str(task_request.get("request_id") or task_request.get("task_id") or "").strip()
    objective_id = str(task_request.get("objective_id") or "").strip()
    task_class = str(task_request.get("task_class") or "").strip()
    validation_only = bool(task_request.get("validation_only"))
    completion_gate = task_request.get("completion_gate") if isinstance(task_request.get("completion_gate"), dict) else {}
    changed_required = bool(completion_gate.get("changed_files_required_for_success"))
    target_file = str(task_request.get("target_file") or "").strip()
    target_files = task_request.get("target_files") if isinstance(task_request.get("target_files"), list) else []
    patch_type = str(task_request.get("patch_type") or task_request.get("edit_mode") or "").strip()
    minimal_patch_plan = task_request.get("minimal_patch_plan")
    validation_plan = task_request.get("validation_plan")
    bounded_edit_mode = bool(task_request.get("bounded_edit_mode"))
    old_text_or_anchor = str(
        task_request.get("exact_current_anchor_or_old_text")
        or task_request.get("old_text_or_anchor")
        or task_request.get("anchor_or_old_text")
        or ""
    ).strip()
    new_text_or_snippet = str(task_request.get("new_text_or_snippet") or "").strip()
    has_target = bool(target_file) or len([item for item in target_files if str(item).strip()]) == 1
    has_patch_plan = bool(patch_type) or (
        isinstance(minimal_patch_plan, dict) and bool(minimal_patch_plan)
    ) or (
        isinstance(minimal_patch_plan, list) and bool(minimal_patch_plan)
    )
    has_validation_plan = bool(validation_plan)
    has_bounded_edit_directives = (not bounded_edit_mode) or (
        bool(patch_type) and bool(old_text_or_anchor) and bool(new_text_or_snippet)
    )
    implementation_shaped = (
        task_class == "implementation"
        and not validation_only
        and changed_required
        and has_target
        and has_patch_plan
        and has_validation_plan
        and has_bounded_edit_directives
    )
    pieces = [
        "implementation_shaped" if implementation_shaped else "not_implementation_shaped",
        f"request={request_id or 'missing'}",
    ]
    if objective_id:
        pieces.append(f"objective={objective_id}")
    pieces.extend(
        [
            f"task_class={task_class or 'missing'}",
            f"validation_only={str(validation_only).lower()}",
            f"changed_files_required_for_success={str(changed_required).lower()}",
            f"target={'present' if has_target else 'missing'}",
            f"patch_plan={'present' if has_patch_plan else 'missing'}",
            f"validation_plan={'present' if has_validation_plan else 'missing'}",
            f"bounded_edit_directives={'present' if has_bounded_edit_directives else 'missing'}",
        ]
    )
    if implementation_shaped:
        return (
            "; ".join(pieces),
            "Allow TOD to execute or publish a precise inspected blocker; verify changed files and validation before credit.",
            False,
        )
    missing = []
    if task_class != "implementation":
        missing.append("task_class=implementation")
    if validation_only:
        missing.append("validation_only=false")
    if not changed_required:
        missing.append("changed_files_required_for_success=true")
    if not has_target:
        missing.append("one target_file")
    if not has_patch_plan:
        missing.append("patch_type/minimal_patch_plan")
    if not has_validation_plan:
        missing.append("validation_plan")
    if not has_bounded_edit_directives:
        missing.append("edit_mode + old_text_or_anchor + new_text_or_snippet")
    return (
        "; ".join(pieces),
        "MIM must convert the current request into one bounded implementation task before TOD execution credit: "
        + ", ".join(missing),
        True,
    )


def _mim_replan_churn_current(
    task_request: dict[str, Any],
    execution_result: dict[str, Any],
    selector: dict[str, Any],
) -> tuple[str, str]:
    request_id = str(task_request.get("request_id") or task_request.get("task_id") or "").strip()
    request_objective = str(task_request.get("objective_id") or "").strip()
    request_status = str(
        task_request.get("status") or task_request.get("result_status") or task_request.get("request_status") or ""
    ).strip().lower()
    execution_id = str(execution_result.get("task_id") or execution_result.get("request_id") or "").strip()
    execution_objective = str(execution_result.get("objective_id") or "").strip()
    execution_status = str(execution_result.get("result_status") or execution_result.get("status") or "").strip().lower()
    execution_reason = str(execution_result.get("reason_code") or "").strip()
    selection_kind = str(selector.get("selection_kind") or "").strip()
    selector_dispatch = str(selector.get("dispatch_status") or "").strip()
    selector_objective = str(selector.get("source_objective") or selector.get("objective_id") or "").strip()
    request_ts = _generated_at_timestamp(task_request)
    execution_ts = _generated_at_timestamp(execution_result)
    selector_ts = _generated_at_timestamp(selector)

    same_objective = (
        bool(request_objective)
        and (
            request_objective == execution_objective
            or request_objective == selector_objective
            or (not selector_objective and bool(selection_kind))
        )
    )
    pending_replan = request_status in {"pending", "published", ""} and "-replan-" in request_id
    newer_than_execution = bool(request_ts and execution_ts and request_ts > execution_ts and request_id != execution_id)
    newer_than_selector = bool(request_ts and selector_ts and request_ts > selector_ts)
    follows_no_viable_selector = (
        selection_kind == "blocked_no_viable_behavior_candidate"
        and selector_dispatch == "blocked_with_reason"
        and bool(selector_ts)
    )
    execution_is_materialization_blocker = (
        execution_status in {"blocked", "blocked_with_inspection"}
        and execution_reason in {"blocked_missing_bounded_edit_mode", "bounded_executor_blocked_with_inspection"}
    )

    if (
        same_objective
        and pending_replan
        and newer_than_execution
        and follows_no_viable_selector
        and execution_is_materialization_blocker
    ):
        current = (
            f"active_replan_churn_no_credit; pending={request_id}; previous_execution={execution_id}; "
            f"objective={request_objective}; selector={selection_kind}; reason={execution_reason}"
        )
        next_action = (
            "MIM should stop issuing same-objective replans until TOD either selects a different current-code target "
            "with a behavior-changing packet or keeps the no-viable-candidate blocker active with inspected files."
        )
        return current, next_action

    if (
        same_objective
        and pending_replan
        and newer_than_selector
        and newer_than_execution
        and follows_no_viable_selector
    ):
        current = (
            f"pending_replan_waiting_on_fresh_selector; pending={request_id}; "
            f"previous_execution={execution_id or 'none'}; selector={selection_kind}; objective={request_objective}"
        )
        next_action = (
            "TOD must answer the freshness gate by publishing a fresh inspected no-viable blocker or selecting a "
            "different behavior-changing current-code target; do not count this as independent progress."
        )
        return current, next_action

    if follows_no_viable_selector and execution_is_materialization_blocker:
        return (
            f"watching_after_no_viable_selector; latest_request={request_id or 'none'}; latest_execution={execution_id or 'none'}",
            "Keep the no-viable selector visible unless a genuinely different behavior-changing target appears.",
        )

    return (
        "not detected",
        "No same-objective replan churn detected; continue normal TOD materialization monitoring.",
    )


def _tod_material_execution_current(
    active_task: dict[str, Any],
    execution_result: dict[str, Any] | None = None,
) -> str:
    task_id = str(active_task.get("task_id") or active_task.get("request_id") or "").strip()
    if not task_id:
        return "no current TOD active task artifact"
    status = str(active_task.get("status") or "unknown").strip()
    _, latest_selector = _freshest_tod_next_task_selection()
    selector_request_id = str(latest_selector.get("request_id") or "").strip() if latest_selector else ""
    selector_kind = str(latest_selector.get("selection_kind") or "").strip() if latest_selector else ""
    selector_dispatch = str(latest_selector.get("dispatch_status") or "").strip() if latest_selector else ""
    selector_reason = " ".join(str(latest_selector.get("blocked_reason") or latest_selector.get("reason_selected") or "").split()) if latest_selector else ""
    if (
        selector_request_id
        and task_id == selector_request_id
        and selector_dispatch == "blocked_with_reason"
        and selector_kind
    ):
        current = f"selector_blocked_no_material_dispatch; selection={selector_kind}; task={task_id}; no implementation credit"
        if selector_reason:
            current += f"; reason={selector_reason[:180]}"
        return current
    reason_code = str(active_task.get("reason_code") or "").strip()
    execution_result = execution_result or {}
    execution_task_id = str(execution_result.get("task_id") or execution_result.get("request_id") or "").strip()
    if execution_task_id != task_id:
        local_execution_result = _load_json(ROOT / "runtime" / "shared" / "TOD_EXECUTION_RESULT.latest.json")
        local_execution_task_id = str(
            local_execution_result.get("task_id") or local_execution_result.get("request_id") or ""
        ).strip()
        if local_execution_task_id == task_id:
            execution_result = local_execution_result
            execution_task_id = local_execution_task_id
    execution_status = str(execution_result.get("status") or execution_result.get("result_status") or "").strip()
    execution_reason = str(execution_result.get("reason_code") or "").strip()
    execution_summary = " ".join(str(execution_result.get("summary") or "").split())
    changed_files = []
    for source_payload in (active_task, execution_result):
        for field_name in ("files_changed", "changed_files"):
            values = source_payload.get(field_name) if isinstance(source_payload.get(field_name), list) else []
            changed_files.extend(values)
    no_credit_packet = _no_credit_packet_artifact_for_changed_files(changed_files)
    if no_credit_packet is None:
        no_credit_packet = _no_credit_packet_artifact_for_task_id(task_id)
    if no_credit_packet:
        packet_path, packet_payload = no_credit_packet
        packet_status = str(packet_payload.get("status") or "unknown").strip()
        blocker = packet_payload.get("blocker") if isinstance(packet_payload.get("blocker"), dict) else {}
        blocker_reason = " ".join(str(blocker.get("reason") or "").split())
        blocker_next = " ".join(str(blocker.get("required_next_action") or "").split())
        current = (
            f"completed_no_credit_packet_artifact; status={status}; packet_status={packet_status}; "
            f"artifact={packet_path.name}; task={task_id}; no implementation credit"
        )
        if blocker_reason:
            current += f"; reason={blocker_reason[:180]}"
        if blocker_next:
            current += f"; next_action={blocker_next[:180]}"
        return current
    contract = active_task.get("execution_contract") if isinstance(active_task.get("execution_contract"), dict) else {}
    contract_status = str(contract.get("status") or "").strip()
    blockers = active_task.get("blockers") if isinstance(active_task.get("blockers"), list) else []
    blocker = blockers[0] if blockers and isinstance(blockers[0], dict) else {}
    recovery_contract = blocker.get("recovery_contract") if isinstance(blocker.get("recovery_contract"), dict) else {}
    target_candidates = blocker.get("target_file_candidates") if isinstance(blocker.get("target_file_candidates"), list) else []
    target = str(recovery_contract.get("target_file") or (target_candidates[0] if target_candidates else "")).strip()
    next_action = str(recovery_contract.get("next_action") or "").strip()
    if (
        task_id
        and execution_task_id == task_id
        and execution_status.lower() in {"completed", "succeeded", "passed"}
    ):
        files_changed = execution_result.get("files_changed") if isinstance(execution_result.get("files_changed"), list) else []
        validations = execution_result.get("validation_results") if isinstance(execution_result.get("validation_results"), list) else []
        validation_passed = bool(validations) and all(
            bool(item.get("passed")) for item in validations if isinstance(item, dict)
        )
        current = f"completed_material_execution; status={execution_status}; task={task_id}"
        if files_changed:
            current += f"; changed_files={len(files_changed)}"
        if validation_passed:
            current += "; validation=passed"
        if execution_summary:
            current += f"; summary={execution_summary[:140]}"
        return current
    if (
        task_id
        and execution_task_id == task_id
        and execution_status.lower() in {"blocked", "failed"}
        and execution_reason in {"codex_wrapper_only_no_execution", "blocked_missing_bounded_edit_mode"}
    ):
        summary_piece = f"; summary={execution_summary[:140]}" if execution_summary else ""
        return (
            f"active_but_latest_execution_blocked; status={status}; execution_status={execution_status}; "
            f"reason={execution_reason}; task={task_id}{summary_piece}"
        )

    pieces = [f"status={status}"]
    if contract_status:
        pieces.append(f"contract={contract_status}")
    if reason_code:
        pieces.append(f"reason={reason_code}")
    if target:
        pieces.append(f"target={target}")
    if next_action:
        pieces.append(f"next_action={next_action[:180]}")
    pieces.append(f"task={task_id}")
    return "; ".join(pieces)


def _tod_autonomy_loop_current(
    active_task: dict[str, Any],
    task_result: dict[str, Any],
    autonomy_nudge: dict[str, Any],
) -> tuple[str, str]:
    task_id = str(active_task.get("task_id") or active_task.get("request_id") or "").strip()
    status = str(active_task.get("status") or "").strip().lower()
    reason_code = str(active_task.get("reason_code") or "").strip()
    blockers = active_task.get("blockers") if isinstance(active_task.get("blockers"), list) else []
    blocker = blockers[0] if blockers and isinstance(blockers[0], dict) else {}
    recovery_contract = blocker.get("recovery_contract") if isinstance(blocker.get("recovery_contract"), dict) else {}
    target_candidates = blocker.get("target_file_candidates") if isinstance(blocker.get("target_file_candidates"), list) else []
    target = str(recovery_contract.get("target_file") or (target_candidates[0] if target_candidates else "")).strip()
    next_action = str(task_result.get("next_action") or "").strip()
    result_status = str(task_result.get("result_status") or task_result.get("status") or "").strip().lower()
    changed_files = task_result.get("changed_files") if isinstance(task_result.get("changed_files"), list) else []

    if changed_files:
        return (
            f"materialized_candidate_present; changed_files={len(changed_files)}; task={task_id}",
            "Validate behavior change, evidence, prevention lesson, and no Codex-authored patch before independent-resolution credit.",
        )

    nudge_active = bool(autonomy_nudge)
    nudge_objective = str(autonomy_nudge.get("objective") or "").strip()
    repeated_shape = (
        reason_code == "blocked_missing_bounded_edit_mode"
        and ("codex_allowed_after_local_blocked_with_inspection" in next_action or nudge_active)
        and (result_status in {"blocked", "blocked_with_inspection"} or status == "blocked")
    )
    if repeated_shape:
        target_piece = f"; target={target}" if target else ""
        nudge_piece = f"; nudge={nudge_objective}" if nudge_objective else ""
        return (
            f"repeated_autonomy_loop; reason={reason_code}{target_piece}; task={task_id}{nudge_piece}; next_action={next_action or 'bounded_packet_or_smaller_task_required'}",
            "TOD must stop reissuing the same blocked-with-inspection handoff: either publish its own bounded edit packet, or split/archive this task and select a smaller live-path implementation it can patch and validate without Codex.",
        )

    if reason_code:
        target_piece = f"; target={target}" if target else ""
        return (
            f"blocked_once_or_waiting; status={status}; reason={reason_code}{target_piece}; task={task_id}",
            "Watch for one more cycle; if the same blocker repeats, require packet materialization or smaller-task selection.",
        )

    return (
        f"watching; status={status or 'unknown'}; task={task_id or 'unknown'}",
        "Continue monitoring for material changed_files plus validation, or a precise inspected blocker.",
    )


def _tod_codex_handoff_drift_current(active_task: dict[str, Any], task_result: dict[str, Any]) -> str:
    task_id = str(active_task.get("task_id") or active_task.get("request_id") or "").strip()
    reason_code = str(active_task.get("reason_code") or "").strip()
    status = str(active_task.get("status") or "").strip().lower()
    next_action = str(task_result.get("next_action") or "").strip()
    result_status = str(task_result.get("result_status") or task_result.get("status") or "").strip().lower()

    if (
        reason_code == "blocked_missing_bounded_edit_mode"
        and "codex_allowed_after_local_blocked_with_inspection" in next_action
        and (status == "blocked" or result_status in {"blocked", "blocked_with_inspection"})
    ):
        return (
            "handoff_drift_detected; next_action=codex_allowed_after_local_blocked_with_inspection; "
            f"task={task_id}; required=TOD-owned bounded packet or smaller live-path task"
        )
    if reason_code == "blocked_missing_bounded_edit_mode":
        return f"blocked_without_codex_handoff; task={task_id}; required=TOD-owned bounded packet"
    if next_action:
        return f"watching; next_action={next_action[:160]}; task={task_id or 'unknown'}"
    return f"watching; task={task_id or 'unknown'}"


def _tod_result_publisher_truth_current(validation: dict[str, Any]) -> tuple[str, str, bool]:
    if not validation:
        return (
            "unknown; context-sync validation artifact missing",
            "Run context-sync truth repair and refresh scorecards before trusting listener TOD_MIM_TASK_RESULT status.",
            False,
        )
    conflict = bool(validation.get("runtime_truth_conflict_detected"))
    current_status = str(validation.get("current_result_status") or "unknown").strip()
    reason_code = str(validation.get("current_result_reason_code") or "").strip()
    source = str(validation.get("current_result_source") or "unknown").strip()
    summary = " ".join(str(validation.get("runtime_truth_conflict_summary") or "").split())
    if conflict:
        pieces = [
            "conflict_detected",
            f"effective_status={current_status}",
            f"source={source}",
        ]
        if reason_code:
            pieces.append(f"reason={reason_code}")
        if summary:
            pieces.append(f"summary={summary[:180]}")
        return (
            "; ".join(pieces),
            "Keep runtime execution truth authoritative; restart or let the existing listener cycle pick up the publisher fix before treating TOD_MIM_TASK_RESULT success as real.",
            True,
        )
    pieces = [
        "aligned",
        f"effective_status={current_status}",
        f"source={source}",
    ]
    if reason_code:
        pieces.append(f"reason={reason_code}")
    return (
        "; ".join(pieces),
        "No listener/runtime result conflict detected; continue normal TOD execution monitoring.",
        False,
    )


def _overall_readout(
    *,
    operator_impact: float | None,
    dave_clarity: int | None,
    stale_count: Any,
    pending_deploy_payload_count: int,
    result_publisher_conflict_requires_action: bool,
    request_shape_requires_action: bool,
    open_dialog_debt_requires_action: bool,
    selection_blocker_requires_action: bool,
    selection_blocker_issue: str = "TOD smaller-task selection is still blocked",
) -> str:
    issues: list[str] = []
    if operator_impact is None:
        issues.append("MIM operator impact needs a live scorecard run")
    elif operator_impact < 8:
        issues.append(f"MIM operator impact is below target ({operator_impact:.1f}/10)")
    if dave_clarity is None:
        issues.append("Dave-needed clarity needs a scorecard run")
    elif dave_clarity < 90:
        issues.append(f"Dave-needed clarity is below target ({dave_clarity}%)")
    if stale_count not in (0, "0"):
        issues.append(f"stale artifact count is not zero ({stale_count})")
    if pending_deploy_payload_count > 0:
        issues.append(f"{pending_deploy_payload_count} MIM deploy payload(s) still need live verification")
    if result_publisher_conflict_requires_action:
        issues.append("TOD result publisher still has listener/runtime truth conflict")
    if request_shape_requires_action:
        issues.append("MIM latest TOD request is not implementation-shaped")
    if open_dialog_debt_requires_action:
        issues.append("open MIM/TOD dialog debt still requires owner action")
    if selection_blocker_requires_action:
        issues.append(selection_blocker_issue)
    if not issues:
        return "Real movement contract is currently on track."
    return "Real movement needs action: " + "; ".join(issues) + "."


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _write_md(path: Path, payload: dict[str, Any]) -> None:
    lines = [
        "# MIM TOD Real Movement Training V1",
        "",
        f"Generated: {payload['generated_at']}",
        f"Status: {payload['status']}",
        f"Overall: {payload['overall_readout']}",
        "",
        "## Required Movement Loop",
        "",
    ]
    for item in payload["required_loop"]:
        lines.append(f"- {item}")
    lines.extend(["", "## Metrics", ""])
    for metric in payload["metrics"]:
        lines.append(f"- {metric['metric']}: {metric['current']} ({metric['target']})")
    lines.extend(["", "## Cycle 001", ""])
    for action in payload["cycle_001"]["actions"]:
        lines.append(f"- {action['action']}")
        lines.append(f"  Owner: {action['owner']}")
        lines.append(f"  Evidence: {action['evidence']}")
        lines.append(f"  Aging: {action['aging']}")
        lines.append(f"  Dave needed: {action['dave_needed']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _strict_independent_resolution_proofs(root: Path) -> list[dict[str, Any]]:
    proofs: list[tuple[float, dict[str, Any]]] = []
    if not root.exists():
        return []
    for path in root.glob("*INDEPENDENT_RESOLUTION_PROOF*.json"):
        payload = _load_json(path)
        if not payload:
            continue
        credit = payload.get("credit_decision") if isinstance(payload.get("credit_decision"), dict) else {}
        if not all(
            bool(credit.get(key))
            for key in (
                "validated_tod_edit",
                "meaningful_tod_implementation",
                "independent_tod_resolution",
            )
        ):
            continue
        if bool(payload.get("codex_patch_supplied")):
            continue
        changed_files_raw = payload.get("changed_files")
        if isinstance(changed_files_raw, list):
            changed_files = [str(item).strip() for item in changed_files_raw if str(item).strip()]
        elif isinstance(changed_files_raw, str) and changed_files_raw.strip():
            changed_files = [changed_files_raw.strip()]
        else:
            changed_files = []
        if not changed_files:
            continue
        validation_results = payload.get("validation_results") if isinstance(payload.get("validation_results"), list) else []
        if not validation_results or not all(bool(item.get("passed")) for item in validation_results if isinstance(item, dict)):
            continue
        proofs.append(
            (
                _generated_at_timestamp(payload) or path.stat().st_mtime,
                {
                    "task_id": str(payload.get("task_id") or path.stem).strip(),
                    "changed_files": changed_files,
                    "validation": "passed",
                    "complexity_level": int(payload.get("complexity_level") or 0),
                    "source": path.name,
                },
            )
        )
    proofs.sort(key=lambda item: item[0])
    return [proof for _timestamp, proof in proofs]


def _write_ladder_md(path: Path, title: str, payload: dict[str, Any]) -> None:
    lines = [
        f"# {title}",
        "",
        f"Generated: {payload.get('generated_at', '')}",
        f"Status: {payload.get('status', '')}",
        "",
    ]
    if "goal" in payload:
        lines.extend(["## Goal", "", str(payload["goal"]), ""])
    if "progress" in payload:
        progress = payload["progress"] if isinstance(payload["progress"], dict) else {}
        lines.extend(
            [
                "## Progress",
                "",
                f"- Strict proofs: {progress.get('current', '')} / {progress.get('target', '')}",
                f"- Current level: {payload.get('current_level', '')} {payload.get('current_level_name', '')}",
                "",
            ]
        )
    if "next_action" in payload:
        next_action = payload["next_action"] if isinstance(payload["next_action"], dict) else {}
        lines.extend(
            [
                "## Next Action",
                "",
                f"- Action: {next_action.get('action', '')}",
                f"- Owner: {next_action.get('owner', '')}",
                f"- Evidence: {next_action.get('expected_evidence', '')}",
                f"- Aging: {next_action.get('aging', '')}",
                f"- Dave needed: {next_action.get('dave_needed', '')}",
                "",
            ]
        )
    if "latest_strict_proofs" in payload:
        lines.extend(["## Latest Strict Proofs", ""])
        for proof in payload["latest_strict_proofs"]:
            lines.append(
                f"- {proof.get('task_id', '')}: {', '.join(proof.get('changed_files', []))} "
                f"({proof.get('validation', '')})"
            )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_independent_resolution_ladder(
    *,
    generated_at: str,
    broader_independent_resolution_count: Any,
    independent_attempt: dict[str, Any],
) -> None:
    strict_proofs = _strict_independent_resolution_proofs(TOD_RESULT_ARTIFACTS_ROOT)
    target = 5
    current = len(strict_proofs)
    current_level = 0 if current < target else 1
    status = "level_0_in_progress" if current < target else "level_1_ready"
    current_level_name = (
        "repeat_current_independent_resolution"
        if current < target
        else "add_one_helper_or_function"
    )
    task_id = str(
        independent_attempt.get("task_id")
        or independent_attempt.get("selected_task_id")
        or "TSK-3394"
    )
    next_action_text = (
        f"{task_id} must produce changed files plus validation or a precise inspected blocker."
        if current < target
        else "Dispatch a level-1 task that adds one bounded helper/function with validation."
    )
    remaining = max(0, target - current)
    next_action = {
        "action": (
            f"Run {remaining} more strict level-0 independent resolution proof{'s' if remaining != 1 else ''} before unlocking helper/function complexity."
            if remaining
            else "Run the first level-1 independent implementation task."
        ),
        "owner": "TOD",
        "expected_evidence": "changed_files, validation_results, rollback_note, prevention_lesson, successor_state, and no Codex patch supply",
        "aging": "one active TOD cycle",
        "dave_needed": "no",
    }
    scorecard = {
        "generated_at": generated_at,
        "objective_id": "TOD-INDEPENDENT-RESOLUTION-LADDER-V1",
        "status": status,
        "current_level": current_level,
        "current_level_name": current_level_name,
        "strict_independent_resolution_count": current,
        "strict_independent_resolution_target": target,
        "broader_real_movement_independent_resolution_count": broader_independent_resolution_count,
        "latest_strict_proofs": strict_proofs[-5:],
        "progress": {"current": current, "target": target},
        "level_unlocks": [
            {
                "level": 0,
                "status": "complete" if current >= target else "in_progress",
                "current": current,
                "target": target,
                "next_requirement": next_action_text,
            },
            {
                "level": 1,
                "status": "ready" if current >= target else "locked",
                "unlock_condition": "level 0 reaches 5 strict independent resolutions",
            },
            {"level": 2, "status": "locked", "unlock_condition": "level 1 completes one helper/function addition with validation"},
            {"level": 3, "status": "locked", "unlock_condition": "level 2 completes helper plus test/probe"},
            {"level": 4, "status": "locked", "unlock_condition": "level 3 completes two connected files"},
            {"level": 5, "status": "locked", "unlock_condition": "level 4 completes real regression repair"},
            {"level": 6, "status": "locked", "unlock_condition": "level 5 completes cross-feature behavior"},
        ],
        "next_action": next_action,
        "credit_policy": {
            "counts_as_progress": [
                "changed real code",
                "validated behavior or syntax",
                "TOD selected the problem",
                "TOD selected the target",
                "no Dave intervention",
                "no Codex patch supply",
            ],
            "does_not_count": [
                "wrapper success",
                "packet-only artifact",
                "queued arbitration",
                "stale result reuse",
                "validation-only change",
                "Codex-supplied patch",
            ],
        },
    }
    objective = {
        "generated_at": generated_at,
        "objective_id": "TOD-INDEPENDENT-RESOLUTION-LADDER-V1",
        "status": "active",
        "goal": "Increase TOD implementation complexity only after repeated strict independent resolutions prove real changed-file execution.",
        "current_level": current_level,
        "current_level_name": current_level_name,
        "acceptance": [
            "Level 0 reaches 5 strict independent resolution proofs before helper/function complexity unlocks.",
            "Every counted proof includes changed_files, passing validation, no Codex patch supply, and a prevention lesson.",
            "Packet-only, wrapper-only, queued, or stale-result artifacts do not count.",
        ],
        "progress": {"current": current, "target": target},
        "next_action": next_action,
    }
    next_task = {
        "generated_at": generated_at,
        "objective_id": "TOD-INDEPENDENT-RESOLUTION-LADDER-V1",
        "status": "ready",
        "task_id": f"{task_id}-ladder-watch",
        "source_task_id": task_id,
        "current_level": current_level,
        "task": next_action_text,
        "owner": "TOD",
        "required_evidence": next_action["expected_evidence"],
        "dave_needed": "no",
    }
    _write_json(TRAINING_ROOT / "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_OBJECTIVE.latest.json", objective)
    _write_ladder_md(TRAINING_ROOT / "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_OBJECTIVE.latest.md", "TOD Independent Resolution Ladder V1 Objective", objective)
    _write_json(TRAINING_ROOT / "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_SCORECARD.latest.json", scorecard)
    _write_ladder_md(TRAINING_ROOT / "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_SCORECARD.latest.md", "TOD Independent Resolution Ladder V1 Scorecard", scorecard)
    _write_json(TRAINING_ROOT / "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_NEXT_TASK.latest.json", next_task)
    _write_ladder_md(TRAINING_ROOT / "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_NEXT_TASK.latest.md", "TOD Independent Resolution Ladder V1 Next Task", next_task)


def main() -> None:
    operator_path = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json"
    operator = _load_json(operator_path)
    live_operator_metrics = _live_operator_metrics_if_fresher(
        operator,
        TRAINING_ROOT / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json",
    )
    scoreboard = _load_json(TRAINING_ROOT / "MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    structural = _load_training_scorecard("MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json")
    cross_surface = _load_training_scorecard("MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json")
    context_grounding = _load_training_scorecard("MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json")
    idle = _load_json(CONTEXT_SYNC_ROOT / "TOD_IDLE_TRAINING_STATUS.latest.json")
    dispatcher = _load_json(CONTEXT_SYNC_ROOT / "MIM_READY_TASK_DISPATCHER_STATUS.latest.json")
    context_sync_validation_path = CONTEXT_SYNC_ROOT / "listener" / "MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json"
    context_sync_validation = _load_json(context_sync_validation_path)
    (
        result_publisher_truth_current,
        result_publisher_truth_next_action,
        result_publisher_conflict_requires_action,
    ) = _tod_result_publisher_truth_current(context_sync_validation)
    tod_task_request_path, tod_task_request = _freshest_tod_task_request(
        [
            CONTEXT_SYNC_ROOT / "listener" / "MIM_TOD_TASK_REQUEST.latest.json",
            TOD_TASK_REQUEST_PATH,
            RUNTIME_TOD_TASK_REQUEST_PATH,
        ]
    )
    (
        mim_tod_request_shape_current,
        mim_tod_request_shape_next_action,
        request_shape_requires_action,
    ) = _mim_tod_request_shape_current(tod_task_request)
    tod_execution_result_paths = [
        ROOT / "runtime" / "shared" / "TOD_EXECUTION_RESULT.latest.json",
        CONTEXT_SYNC_ROOT / "listener" / "TOD_EXECUTION_RESULT.latest.json",
        TOD_LISTENER_RESULT_PATH,
        ROOT / "runtime" / "logs" / "mim_tod_reflection_pull" / "TOD_MIM_TASK_RESULT.latest.json",
    ]
    tod_execution_result_path, tod_execution_result = _freshest_tod_execution_result(
        tod_execution_result_paths,
        tod_task_request,
    )
    tod_latest_execution_result_path, tod_latest_execution_result = _freshest_tod_execution_result(
        tod_execution_result_paths,
    )
    tod_task_result_path, tod_task_result = _freshest_json(
        [TRAINING_TOD_TASK_RESULT_PATH, TOD_LISTENER_RESULT_PATH, TOD_REFLECTION_PULL_RESULT_PATH]
    )
    tod_active_task = _load_json(RUNTIME_TOD_ACTIVE_TASK_PATH)
    tod_material_execution_result = tod_latest_execution_result or tod_execution_result
    tod_material_execution_result_path = tod_latest_execution_result_path if tod_latest_execution_result else tod_execution_result_path
    current_request_ids = {
        str(tod_task_request.get("request_id") or "").strip(),
        str(tod_task_request.get("task_id") or "").strip(),
    }
    current_request_ids = {item for item in current_request_ids if item}
    tod_execution_result_id = str(
        tod_execution_result.get("task_id") or tod_execution_result.get("request_id") or ""
    ).strip()
    if current_request_ids and tod_execution_result_id in current_request_ids:
        if _execution_result_materiality_rank(tod_execution_result) >= _execution_result_materiality_rank(
            tod_material_execution_result
        ):
            tod_material_execution_result = tod_execution_result
            tod_material_execution_result_path = tod_execution_result_path
        if _execution_result_materiality_rank(tod_execution_result) > _execution_result_materiality_rank(tod_task_result):
            tod_task_result = tod_execution_result
            tod_task_result_path = tod_execution_result_path
    if tod_material_execution_result and _generated_at_timestamp(tod_material_execution_result) > _generated_at_timestamp(tod_active_task):
        tod_active_task = tod_material_execution_result
    codex_allowed_not_patch_nudge = _load_json(CODEX_ALLOWED_NOT_CODEX_PATCH_NUDGE_PATH)
    completed_drills = _completed_blocker_drills()
    patch_synthesis_practice = _load_json(PATCH_SYNTHESIS_PRACTICE_PATH)
    selection_blocker = _load_json(SELECTION_BLOCKER_PATH)
    dedupe_guard_path, dedupe_guard = _latest_dedupe_guard(CODEX_TRAINING_INTERVENTIONS_ROOT)
    daemon_health_path, daemon_health = _latest_intervention(
        CODEX_TRAINING_INTERVENTIONS_ROOT,
        "CODEX_TOD_AUTONOMOUS_DAEMON_HEALTH_*.latest.json",
    )
    daemon_health_current, daemon_health_next_action = _tod_autonomous_daemon_health_current(daemon_health)
    dialog_inbox_health_path, dialog_inbox_health = _latest_intervention(
        CODEX_TRAINING_INTERVENTIONS_ROOT,
        "CODEX_TOD_DIALOG_INBOX_READ_HEALTH_*.latest.json",
    )
    dialog_inbox_health_current, dialog_inbox_health_next_action = _tod_dialog_inbox_health_current(dialog_inbox_health)
    dialog_consumption_path, dialog_consumption = _latest_intervention(
        CODEX_TRAINING_INTERVENTIONS_ROOT,
        "CODEX_TOD_GOVERNED_DIALOG_CONSUMPTION_GAP_*.latest.json",
    )
    dialog_consumption_current, dialog_consumption_next_action = _tod_governed_dialog_consumption_current(
        dialog_consumption
    )
    dialog_consumption_source = dialog_consumption_path.name if dialog_consumption_path else "codex_training_interventions"
    governed_dispatch_path, governed_dispatch = _latest_intervention(
        CODEX_TRAINING_INTERVENTIONS_ROOT,
        "CODEX_TOD_GOVERNED_INBOX_CONSUMER_DISPATCH_*.latest.json",
    )
    governed_dispatch_current, governed_dispatch_next_action = _tod_governed_inbox_consumer_dispatch_current(
        governed_dispatch
    )
    if governed_dispatch_current:
        dialog_consumption_current = governed_dispatch_current
        dialog_consumption_next_action = governed_dispatch_next_action
        dialog_consumption_source = governed_dispatch_path.name if governed_dispatch_path else dialog_consumption_source
    materialization_timeout_current, materialization_timeout_source, materialization_timeout_next_action = (
        _tod_materialization_timeout_current(CODEX_TRAINING_INTERVENTIONS_ROOT)
    )
    different_target_discovery_current, different_target_discovery_source, different_target_discovery_next_action = (
        _tod_different_target_discovery_current(CODEX_TRAINING_INTERVENTIONS_ROOT)
    )
    packet_capability_current, packet_capability_source, packet_capability_next_action = (
        _tod_current_code_packet_capability_current(INDEPENDENT_ATTEMPTS_ROOT, CODEX_TRAINING_INTERVENTIONS_ROOT)
    )
    studio_target_packet_current, studio_target_packet_source, studio_target_packet_next_action = (
        _tod_studio_target_packet_materialization_current(CODEX_TRAINING_INTERVENTIONS_ROOT)
    )
    recovery_packet_regression_current, recovery_packet_regression_source, recovery_packet_regression_next_action = (
        _tod_recovery_packet_regression_current(CODEX_TRAINING_INTERVENTIONS_ROOT)
    )
    tsk3394_material_push_path, tsk3394_material_push = _latest_intervention(
        CODEX_TRAINING_INTERVENTIONS_ROOT,
        "CODEX_TOD_TSK3394_MATERIAL_EXECUTION_PUSH_*.latest.json",
    )
    tsk3394_material_push_current, tsk3394_material_push_next_action = _tod_tsk3394_material_push_current(
        tsk3394_material_push
    )
    tsk3394_material_push_source = (
        tsk3394_material_push_path.name if tsk3394_material_push_path else "codex_training_interventions"
    )
    packet_loop_current, packet_loop_source, packet_loop_next_action = _packet_formation_loop_current(
        INDEPENDENT_ATTEMPTS_ROOT
    )
    patch_synthesis_practice_backup_path, patch_synthesis_practice_backup = _latest_patch_synthesis_practice_backup(
        LOCAL_ENGINE_BACKUPS_ROOT
    )
    independent_attempt_path, independent_attempt = _latest_independent_candidate_attempt(INDEPENDENT_ATTEMPTS_ROOT)
    packet_gate_timestamp = _earliest_packet_gate_timestamp(INDEPENDENT_ATTEMPTS_ROOT)
    latest_selector_path, latest_selector = _freshest_tod_next_task_selection()
    no_viable_inspection_current, no_viable_inspection_source, no_viable_inspection_next_action = (
        _no_viable_candidate_inspection_current(latest_selector, tod_material_execution_result)
    )
    replan_churn_current, replan_churn_next_action = _mim_replan_churn_current(
        tod_task_request,
        tod_material_execution_result,
        latest_selector,
    )
    selection_blocker_current = _tod_selection_blocker_current(selection_blocker)
    selection_blocker_source = SELECTION_BLOCKER_PATH.name
    selection_blocker_next_action = _tod_selection_blocker_next_action(selection_blocker)
    if _selector_supersedes_dialog_blocker(selection_blocker, latest_selector):
        (
            selection_blocker_current,
            selection_blocker_source,
            selection_blocker_next_action,
        ) = _selection_blocker_from_selector(latest_selector)
    if latest_selector and _generated_at_timestamp(latest_selector) >= _generated_at_timestamp(independent_attempt):
        independent_attempt_path = latest_selector_path
        independent_attempt = latest_selector
    independent_candidate_current, independent_candidate_source, independent_candidate_next_action = _independent_candidate_current(
        independent_attempt_path,
        independent_attempt,
    )
    tod_autonomy_loop_current, tod_autonomy_loop_next_action = _tod_autonomy_loop_current(
        tod_active_task,
        tod_task_result,
        codex_allowed_not_patch_nudge,
    )
    tod_codex_handoff_drift_current = _tod_codex_handoff_drift_current(tod_active_task, tod_task_result)
    missing_bounded_selector_fields = _selector_missing_bounded_fields(independent_attempt)
    selector_field_completeness_current, selector_field_completeness_next_action = (
        _selector_field_completeness_current(independent_attempt, missing_bounded_selector_fields)
    )
    tod_material_execution_current = _tod_material_execution_current(tod_active_task, tod_material_execution_result)
    selection_blocker_issue = "TOD smaller-task selection is still blocked"
    selector_dispatch_status = str(independent_attempt.get("dispatch_status") or "").strip().lower()
    selector_selection_kind = str(independent_attempt.get("selection_kind") or "").strip().lower()
    selector_completed_candidate = (
        selector_dispatch_status in {"completed", "succeeded", "passed"}
        and selector_selection_kind == "synthesized_independent_resolution_candidate"
    )
    if (
        missing_bounded_selector_fields
        and str(independent_attempt.get("selected_task_id") or "").strip()
        and not selector_completed_candidate
    ):
        (
            independent_candidate_current,
            independent_candidate_source,
            independent_candidate_next_action,
        ) = _invalid_partial_selector_current(
            independent_attempt_path,
            independent_attempt,
            missing_bounded_selector_fields,
        )
    if _artifact_write_repair_supersedes_candidate(
        independent_attempt_path,
        independent_attempt,
        PATCH_SYNTHESIS_PRACTICE_PATH,
        patch_synthesis_practice,
    ):
        independent_candidate_current = (
            "artifact_write_validated_by_practice_artifact; "
            "selection=awaiting_next_materialized_live_candidate; dispatch=not_yet_retried_after_repair"
        )
        independent_candidate_source = PATCH_SYNTHESIS_PRACTICE_PATH.name
        independent_candidate_next_action = (
            "Rerun independent-resolution candidate selection after the listener reloads current target-hint ingestion. "
            "Do not spend another cycle on artifact_write; it has current LocalExecutionEngine validation evidence."
        )

    material_execution_completed = "completed_material_execution" in tod_material_execution_current
    selector_fields_complete = selector_field_completeness_current.startswith("complete;")
    packet_capability_ready = "packet_candidate_ready" in packet_capability_current
    effective_request_shape_requires_action = request_shape_requires_action and not material_execution_completed
    if material_execution_completed and selector_fields_complete:
        previous_selection_blocker_current = selection_blocker_current
        selection_blocker_current = (
            "superseded_by_packet_candidate_execution; "
            f"selector={selector_field_completeness_current}; execution={tod_material_execution_current}"
        )
        selection_blocker_source = f"{latest_selector_path.name} + {tod_material_execution_result_path.name}"
        selection_blocker_next_action = (
            "Do not keep the historical smaller-task blocker as current. Continue with the next TOD-owned "
            "independent-resolution candidate, but do not inflate independent-resolution credit from this Codex-assisted lane."
        )
        if previous_selection_blocker_current:
            selection_blocker_next_action += f" Previous blocker retained as historical evidence: {previous_selection_blocker_current[:180]}"
    if material_execution_completed and packet_capability_ready:
        studio_target_packet_current = (
            "superseded_by_current_packet_materialization; "
            f"packet={packet_capability_current}; execution={tod_material_execution_current}"
        )
        studio_target_packet_source = f"{packet_capability_source} + {tod_material_execution_result_path.name}"
        studio_target_packet_next_action = (
            "Treat older Studio packet materialization blockers as historical. The current packet was formed and executed; "
            "the next challenge is a genuinely TOD-owned independent resolution without Codex capability repair."
        )
    if (
        "blocked_no_viable_candidate" in independent_candidate_current
        and "TOD_DIFFERENT_TARGET_DISCOVERY_DRILL" in independent_candidate_source
    ):
        selection_blocker_current = (
            "superseded_by_evidenced_no_viable_discovery; "
            f"candidate_state={independent_candidate_current}; material={tod_material_execution_current}"
        )
        selection_blocker_source = f"{independent_candidate_source} + {tod_material_execution_result_path.name}"
        selection_blocker_next_action = independent_candidate_next_action
        selection_blocker_issue = (
            "TOD discovery candidate set is exhausted; broaden discovery definitions or inspect a new live-code surface"
        )
    elif (
        "candidate_selected" in independent_candidate_current
        and "TOD_DIFFERENT_TARGET_DISCOVERY_DRILL" in independent_candidate_source
    ):
        selection_blocker_current = (
            "superseded_by_selected_live_code_candidate; "
            f"candidate_state={independent_candidate_current}; material={tod_material_execution_current}"
        )
        selection_blocker_source = f"{independent_candidate_source} + {tod_material_execution_result_path.name}"
        selection_blocker_next_action = (
            "Dispatch the selected live-code candidate as a separate TOD-owned implementation with changed files, "
            "focused validation, rollback note, and prevention lesson before any independent-resolution credit."
        )
        selection_blocker_issue = "TOD selected a live-code candidate; implementation and validation are still pending"

    operator_metrics = (
        live_operator_metrics
        if live_operator_metrics is not None
        else operator.get("metrics") if isinstance(operator.get("metrics"), list) else []
    )
    operator_impact = _operator_score(_metric_current(operator_metrics, "Operator Impact"))
    dave_clarity = _parse_percent(_metric_current(operator_metrics, "Dave Needed Clarity"))
    structural_pass = structural.get("weighted_pass_rate")
    structural_current = (
        f"{round(float(structural_pass) * 100)}% weighted pass; score {structural.get('weighted_structural_score', 'unknown')}/10"
        if isinstance(structural_pass, (int, float))
        else "needs scorecard run"
    )
    if cross_surface:
        cross_surface_current = (
            f"{cross_surface.get('status', 'unknown')}; "
            f"{cross_surface.get('target_met_surface_count', 0)}/{cross_surface.get('surface_count', 0)} surfaces target met"
        )
    else:
        cross_surface_current = "needs scorecard run"
    context_grounding_pass = context_grounding.get("weighted_pass_rate")
    context_grounding_current = (
        f"{round(float(context_grounding_pass) * 100)}% weighted pass; score {context_grounding.get('weighted_context_score', 'unknown')}/10"
        if isinstance(context_grounding_pass, (int, float))
        else "needs scorecard run"
    )

    reflection = scoreboard.get("outcome_reflection") if isinstance(scoreboard.get("outcome_reflection"), dict) else {}
    tod_score = scoreboard.get("tod_score") if isinstance(scoreboard.get("tod_score"), dict) else {}
    artifact_metrics = tod_score.get("artifact_metrics") if isinstance(tod_score.get("artifact_metrics"), dict) else {}
    if not artifact_metrics:
        artifact_metrics = tod_score.get("metrics") if isinstance(tod_score.get("metrics"), dict) else {}
    deploy_payloads = tod_score.get("deploy_payloads") if isinstance(tod_score.get("deploy_payloads"), dict) else {}
    latest_deploy_payload = deploy_payloads.get("latest") if isinstance(deploy_payloads.get("latest"), dict) else {}
    pending_deploy_payload_count = _coerce_int(deploy_payloads.get("pending_count")) or 0
    pending_deploy_current = (
        f"{pending_deploy_payload_count} pending"
        if pending_deploy_payload_count
        else "0 pending"
    )
    latest_deploy_objective = str(latest_deploy_payload.get("objective_id") or "").strip()
    latest_deploy_file = str(latest_deploy_payload.get("file") or "").strip()
    if latest_deploy_objective:
        pending_deploy_current += f"; latest={latest_deploy_objective}"
    if latest_deploy_file:
        pending_deploy_current += f"; file={latest_deploy_file}"

    stale_count = reflection.get("stale_artifact_count", "unknown")
    blocked_count = reflection.get("operator_summary", "")
    validated_edits = artifact_metrics.get("validated_edits", {})
    if isinstance(validated_edits, dict):
        validated_edits_value = validated_edits.get("value", "unknown")
        validated_edits_source = str(validated_edits.get("source") or "tod_result_artifacts")
    else:
        validated_edits_value = validated_edits
        validated_edits_source = "tod_result_artifacts"
    validated_edits_base = _coerce_int(validated_edits)
    meaningful_implementations = artifact_metrics.get("meaningful_tod_implementations", {})
    if isinstance(meaningful_implementations, dict):
        meaningful_implementations_value = meaningful_implementations.get("value", "unknown")
    else:
        meaningful_implementations_value = meaningful_implementations
    independent_resolutions = artifact_metrics.get("independent_tod_resolutions", {})
    if isinstance(independent_resolutions, dict):
        independent_resolutions_value = independent_resolutions.get("value", "unknown")
        independent_resolution_source = str(independent_resolutions.get("source") or "tod_result_artifacts")
    else:
        independent_resolutions_value = independent_resolutions
        independent_resolution_source = "tod_result_artifacts"
    independent_resolution_base = _coerce_int(independent_resolutions)
    has_state_proven_pending_metric = "state_proven_local_completions_pending_independent_proof" in artifact_metrics
    state_proven_pending = artifact_metrics.get("state_proven_local_completions_pending_independent_proof", {})
    if isinstance(state_proven_pending, dict):
        state_proven_pending_value = state_proven_pending.get("value", "unknown")
        state_proven_pending_source = str(state_proven_pending.get("source") or "tod/data/state.json")
    else:
        state_proven_pending_value = state_proven_pending
        state_proven_pending_source = "tod/data/state.json"
    effective_tod_state_path = TOD_STATE_PATH
    try:
        effective_tod_state_path.resolve().relative_to(ROOT.resolve())
    except ValueError:
        effective_tod_state_path = ROOT / "tod" / "data" / "state.json"
    state_proven_validated_ids = _state_proven_validated_edit_ids(effective_tod_state_path, packet_gate_timestamp)
    state_proven_independent_ids = _state_proven_independent_resolution_ids(effective_tod_state_path, packet_gate_timestamp)
    # Keep the headline aligned with the training scoreboard's stricter ledger.
    # State-only local completions remain visible below as pending proof; adding
    # them here makes the real-movement card disagree with its own source.
    pending_state_already_counted = has_state_proven_pending_metric and "tod/data/state.json" in state_proven_pending_source
    state_proven_pending_base = _coerce_int(state_proven_pending)
    if state_proven_pending_base is None:
        state_proven_pending_base = 0
    state_proven_pending_ids = [
        task_id for task_id in state_proven_validated_ids if task_id not in set(state_proven_independent_ids)
    ]
    if state_proven_pending_ids and not pending_state_already_counted:
        state_proven_pending_value = state_proven_pending_base + len(state_proven_pending_ids)
        state_proven_pending_source = "tod/data/state.json"
    elif state_proven_pending_ids and pending_state_already_counted and state_proven_pending_base < len(state_proven_pending_ids):
        state_proven_pending_value = len(state_proven_pending_ids)
        state_proven_pending_source = "tod/data/state.json"
    open_dialog_debt_current = _open_dialog_debt_current(DIALOG_SESSIONS_PATH)
    active_owner_requests_current = _active_owner_requests_current(DIALOG_SESSIONS_PATH)
    open_dialog_debt_requires_action = not (
        open_dialog_debt_current.startswith("0 open replies")
        or (
            open_dialog_debt_current.startswith("0 unmanaged open replies")
            and "governed_overdue=" not in open_dialog_debt_current
        )
    )
    selection_blocker_requires_action = (
        (
            str(selection_blocker.get("status") or "").strip().lower() == "active_blocker"
            or selection_blocker_current.startswith("superseded_by_evidenced_no_viable_discovery")
        )
        and not selection_blocker_current.startswith("superseded_by_packet_candidate_execution")
    )
    state_already_counted = "tod/data/state.json" in independent_resolution_source
    if independent_resolution_base is not None and state_proven_independent_ids and not state_already_counted:
        state_proven_total = independent_resolution_base + len(state_proven_independent_ids)
        independent_resolutions_value = (
            f"{state_proven_total} "
            f"({independent_resolution_base} scoreboard + {len(state_proven_independent_ids)} state-proven: "
            f"{', '.join(state_proven_independent_ids)})"
        )
        independent_resolution_source = "tod/data/state.json + tod_result_artifacts"

    action_required = (
        operator_impact is None
        or operator_impact < 8
        or dave_clarity is None
        or dave_clarity < 90
        or stale_count not in (0, "0")
        or pending_deploy_payload_count > 0
        or result_publisher_conflict_requires_action
        or effective_request_shape_requires_action
        or open_dialog_debt_requires_action
        or selection_blocker_requires_action
    )
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    payload = {
        "generated_at": now,
        "objective_id": "MIM-TOD-REAL-MOVEMENT-TRAINING-V1",
        "status": "action_required" if action_required else "on_track",
        "overall_readout": _overall_readout(
            operator_impact=operator_impact,
            dave_clarity=dave_clarity,
            stale_count=stale_count,
            pending_deploy_payload_count=pending_deploy_payload_count,
            result_publisher_conflict_requires_action=result_publisher_conflict_requires_action,
            request_shape_requires_action=effective_request_shape_requires_action,
            open_dialog_debt_requires_action=open_dialog_debt_requires_action,
            selection_blocker_requires_action=selection_blocker_requires_action,
            selection_blocker_issue=selection_blocker_issue,
        ),
        "required_loop": [
            "MIM replies include action, owner, evidence, aging, and Dave-needed yes/no.",
            "TOD produces changed files plus validation, or blocks with inspected evidence, every active cycle.",
            "Stale artifacts are retired, refreshed, or mapped to current project state.",
            "Projects older than 24 hours without movement are forced to completed, split, dispatched, waiting-with-evidence, blocked-with-owner, or archived.",
            "Every action records whether it moved the project closer to completion.",
        ],
        "metrics": [
            {
                "metric": "MIM Operator Impact",
                "current": _metric_current(operator_metrics, "Operator Impact"),
                "target": "8/10+",
                "source": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
            },
            {
                "metric": "Dave Needed Clarity",
                "current": _metric_current(operator_metrics, "Dave Needed Clarity"),
                "target": "90%+",
                "source": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
            },
            {
                "metric": "Stale Artifact Count",
                "current": str(stale_count),
                "target": "decrease every cycle until 0 or source-labeled historical",
                "source": "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
            },
            {
                "metric": "Pending MIM Deploy Payloads",
                "current": pending_deploy_current,
                "target": "0 pending, or every payload has deployed/verified/closed evidence",
                "source": "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
            },
            {
                "metric": "TOD Result Publisher Truth",
                "current": result_publisher_truth_current,
                "target": "listener TOD_MIM_TASK_RESULT does not contradict runtime TOD_EXECUTION_RESULT for the same request",
                "source": context_sync_validation_path.name,
            },
            {
                "metric": "TOD Result Publisher Next Action",
                "current": result_publisher_truth_next_action,
                "target": "publisher fix is reflected in live latest artifacts before success is credited",
                "source": context_sync_validation_path.name,
            },
            {
                "metric": "MIM TOD Request Shape",
                "current": mim_tod_request_shape_current,
                "target": "implementation-shaped request with one target file, patch plan, validation plan, and changed-files success gate",
                "source": tod_task_request_path.name,
            },
            {
                "metric": "MIM TOD Request Shape Next Action",
                "current": mim_tod_request_shape_next_action,
                "target": "MIM dispatches a bounded executable task instead of diagnostic/status-only work",
                "source": tod_task_request_path.name,
            },
            {
                "metric": "Open MIM/TOD Dialog Debt",
                "current": open_dialog_debt_current,
                "target": "0 open replies, or every open reply has owner, evidence request, and aging rule",
                "source": DIALOG_SESSIONS_PATH.name,
            },
            {
                "metric": "Open Dialog Debt Next Action",
                "current": _open_dialog_debt_next_action(open_dialog_debt_current),
                "target": "oldest open reply is closed, owner-labeled, or evidence-aged before new training work",
                "source": DIALOG_SESSIONS_PATH.name,
            },
            {
                "metric": "TOD Dialog Inbox Read Health",
                "current": dialog_inbox_health_current,
                "target": "TOD inbox health reads return quickly enough to distinguish no open work from responder silence",
                "source": dialog_inbox_health_path.name if dialog_inbox_health_path else "codex_training_interventions",
            },
            {
                "metric": "TOD Dialog Inbox Next Action",
                "current": dialog_inbox_health_next_action,
                "target": "monitor path is verified before diagnosing TOD capability failure",
                "source": dialog_inbox_health_path.name if dialog_inbox_health_path else "codex_training_interventions",
            },
            {
                "metric": "TOD Governed Dialog Consumption",
                "current": dialog_consumption_current,
                "target": "TOD consumes MIM-to-TOD governed handoff requests or reports a current blocker before aging out",
                "source": dialog_consumption_source,
            },
            {
                "metric": "TOD Governed Dialog Consumption Next Action",
                "current": dialog_consumption_next_action,
                "target": "next action names the TOD-owned consumer repair before more patch prompts are sent",
                "source": dialog_consumption_source,
            },
            {
                "metric": "Active Owner Request State",
                "current": active_owner_requests_current,
                "target": "every active Codex owner request has one owner, one evidence ask, one aging rule, and no duplicate successor",
                "source": DIALOG_SESSIONS_PATH.name,
            },
            {
                "metric": "TOD UI Handoff Dedupe Guard",
                "current": _dedupe_guard_current(dedupe_guard),
                "target": "TOD UI handoff retries reuse active blocker/handoff instead of creating duplicate dialog debt",
                "source": dedupe_guard_path.name if dedupe_guard_path else "CODEX_TOD_UI_HANDOFF_DEDUPE_GUARD_*.latest.json",
            },
            {
                "metric": "TOD Smaller-Task Selection Blocker",
                "current": selection_blocker_current,
                "target": "TOD returns one smaller code task with target file, target rule/function, expected changed files, validation command, rollback note, and prevention lesson",
                "source": selection_blocker_source,
            },
            {
                "metric": "TOD Selection Blocker Next Action",
                "current": selection_blocker_next_action,
                "target": "no implementation dispatch or independent-resolution credit until smaller-task selection evidence exists",
                "source": selection_blocker_source,
            },
            {
                "metric": "Validated TOD Edits",
                "current": str(validated_edits_value),
                "target": "30+ strict validated edits with no wrapper-only completion",
                "source": validated_edits_source,
            },
            {
                "metric": "Meaningful TOD Implementations",
                "current": str(meaningful_implementations_value),
                "target": "changed real code, changed behavior, validation passed, live path affected",
                "source": "tod_result_artifacts",
            },
            {
                "metric": "Independent TOD Resolutions",
                "current": str(independent_resolutions_value),
                "target": "TOD identifies, fixes, validates, and resolves with no Dave/Codex",
                "source": independent_resolution_source,
            },
            {
                "metric": "State-Proven Local Completions Pending Independent Proof",
                "current": str(state_proven_pending_value),
                "target": "visible but not counted as independent until problem/fix/meaningful implementation proof exists",
                "source": state_proven_pending_source,
            },
            {
                "metric": "TOD Packet-Formation Loop",
                "current": packet_loop_current,
                "target": "packet/no-op attempts become terminal blockers instead of repeated selector choices",
                "source": packet_loop_source,
            },
            {
                "metric": "TOD Recovery Packet Regression",
                "current": recovery_packet_regression_current,
                "target": "selector does not abandon a precise Studio blocker for generic recovery packet formation",
                "source": recovery_packet_regression_source,
            },
            {
                "metric": "TOD Recovery Packet Regression Next Action",
                "current": recovery_packet_regression_next_action,
                "target": "selector preference keeps the Studio old_text/new_text blocker active until TOD materializes it or blocks precisely",
                "source": recovery_packet_regression_source,
            },
            {
                "metric": "Independent Resolution Candidate State",
                "current": independent_candidate_current,
                "target": "ready candidate only when one target file, non-validation edit materialization, validation command, and closure evidence are proven",
                "source": independent_candidate_source,
            },
            {
                "metric": "Independent Resolution Next Action",
                "current": (
                    packet_loop_next_action
                    if (
                        "repeated_packet_formation_no_credit" in packet_loop_current
                        and "blocked_current_blocker_packet_target_required" not in independent_candidate_current
                        and "blocked_requires_tod_synthesized_old_new" not in independent_candidate_current
                        and "selection=packet_candidate_code_task" not in independent_candidate_current
                    )
                    else independent_candidate_next_action
                ),
                "target": "TOD has one specific inspected next move instead of vague blocked status",
                "source": (
                    packet_loop_source
                    if (
                        "repeated_packet_formation_no_credit" in packet_loop_current
                        and "blocked_current_blocker_packet_target_required" not in independent_candidate_current
                        and "blocked_requires_tod_synthesized_old_new" not in independent_candidate_current
                        and "selection=packet_candidate_code_task" not in independent_candidate_current
                    )
                    else independent_candidate_source
                ),
            },
            {
                "metric": "TOD Selector Field Completeness",
                "current": selector_field_completeness_current,
                "target": "8/8 bounded selector fields before dispatch or independent-resolution credit",
                "source": independent_attempt_path.name if independent_attempt_path else "TOD_NEXT_TASK_SELECTION.latest.json",
            },
            {
                "metric": "TOD Selector Field Next Action",
                "current": selector_field_completeness_next_action,
                "target": "selector gap is actionable without Codex patching the target",
                "source": independent_attempt_path.name if independent_attempt_path else "TOD_NEXT_TASK_SELECTION.latest.json",
            },
            {
                "metric": "No-Viable Candidate Inspection Evidence",
                "current": no_viable_inspection_current,
                "target": "blocked_no_viable_behavior_candidate includes inspected_files, blocked_reason, and blocker.required_next_action",
                "source": no_viable_inspection_source,
            },
            {
                "metric": "No-Viable Candidate Next Action",
                "current": no_viable_inspection_next_action,
                "target": "next selector cycle has a concrete inspected target path instead of artifact-only status",
                "source": no_viable_inspection_source,
            },
            {
                "metric": "TOD Active Request Alignment",
                "current": _tod_active_request_alignment_current(tod_task_request, tod_execution_result),
                "target": "latest TOD execution matches the current pending TOD request, or publishes inspected blocker evidence",
                "source": f"{tod_task_request_path.name} + {tod_execution_result_path.name}",
            },
            {
                "metric": "MIM Replan Churn State",
                "current": replan_churn_current,
                "target": "same-objective replans do not outrun TOD no-viable or packet-materialization evidence",
                "source": f"{tod_task_request_path.name} + {tod_execution_result_path.name} + TOD_NEXT_TASK_SELECTION.latest.json",
            },
            {
                "metric": "MIM Replan Churn Next Action",
                "current": replan_churn_next_action,
                "target": "MIM/TOD switches to a different current-code target or keeps no-viable blocker active instead of reissuing the same broad replan",
                "source": f"{tod_task_request_path.name} + {tod_execution_result_path.name} + TOD_NEXT_TASK_SELECTION.latest.json",
            },
            {
                "metric": "TOD Material Execution State",
                "current": tod_material_execution_current,
                "target": "material TOD execution is completed only when behavior-changing edit or inspected blocker evidence exists",
                "source": f"{RUNTIME_TOD_ACTIVE_TASK_PATH.name} + {tod_material_execution_result_path.name}",
            },
            {
                "metric": "TOD TSK-3394 Material Execution Push",
                "current": tsk3394_material_push_current,
                "target": "TOD produces changed files plus validation or a target-specific inspected blocker without Codex patch supply",
                "source": tsk3394_material_push_source,
            },
            {
                "metric": "TOD TSK-3394 Material Execution Next Action",
                "current": tsk3394_material_push_next_action,
                "target": "one active TOD cycle produces material proof or no-credit blocker evidence",
                "source": tsk3394_material_push_source,
            },
            {
                "metric": "TOD Materialization Timeout State",
                "current": materialization_timeout_current,
                "target": "bounded-edit materialization timeouts are recorded as no-credit evidence and do not create repeated nudge loops",
                "source": materialization_timeout_source,
            },
            {
                "metric": "TOD Materialization Timeout Next Action",
                "current": materialization_timeout_next_action,
                "target": "next materialization attempt changes the capability path instead of repeating the same request",
                "source": materialization_timeout_source,
            },
            {
                "metric": "TOD Current-Code Packet Capability",
                "current": packet_capability_current,
                "target": "post-timeout packet candidate includes target_file, non-validation edit mode, current old/new or anchor/snippet, validation command, prevention lesson, and Dave-needed",
                "source": packet_capability_source,
            },
            {
                "metric": "TOD Current-Code Packet Next Action",
                "current": packet_capability_next_action,
                "target": "TOD learns to materialize a bounded packet before dispatching another autonomous code task",
                "source": packet_capability_source,
            },
            {
                "metric": "TOD Studio Target Packet Materialization",
                "current": studio_target_packet_current,
                "target": "TOD materializes old_text/new_text or a target-specific blocker for tmp_remote_mim/core/routers/studio.py without pivoting to stale packet backlog",
                "source": studio_target_packet_source,
            },
            {
                "metric": "TOD Studio Target Packet Next Action",
                "current": studio_target_packet_next_action,
                "target": "next action repairs materialization capability before another implementation-credit attempt",
                "source": studio_target_packet_source,
            },
            {
                "metric": "TOD Different-Target Discovery Drill",
                "current": different_target_discovery_current,
                "target": "TOD inspects different current-code files and publishes one fresh candidate or a no-viable blocker before another packet/implementation dispatch",
                "source": different_target_discovery_source,
            },
            {
                "metric": "TOD Different-Target Discovery Next Action",
                "current": different_target_discovery_next_action,
                "target": "target discovery creates candidate evidence without Codex supplying the target patch",
                "source": different_target_discovery_source,
            },
            {
                "metric": "TOD Autonomy Loop State",
                "current": tod_autonomy_loop_current,
                "target": "repeated blocked-with-inspection handoffs become packet materialization or smaller-task selection, not Codex patching",
                "source": f"{RUNTIME_TOD_ACTIVE_TASK_PATH.name} + {tod_task_result_path.name}",
            },
            {
                "metric": "TOD Autonomy Loop Next Action",
                "current": tod_autonomy_loop_next_action,
                "target": "TOD has an autonomy-preserving next move when material execution repeats the same blocker",
                "source": f"{RUNTIME_TOD_ACTIVE_TASK_PATH.name} + {tod_task_result_path.name}",
            },
            {
                "metric": "TOD Codex Handoff Drift",
                "current": tod_codex_handoff_drift_current,
                "target": "blocked-with-inspection recovery does not route implementation ownership back to Codex during TOD autonomy training",
                "source": f"{RUNTIME_TOD_ACTIVE_TASK_PATH.name} + {tod_task_result_path.name}",
            },
            {
                "metric": "TOD Autonomous Daemon Health",
                "current": daemon_health_current,
                "target": "controlled daemon runs either produce valid TOD selector/material evidence or are marked no-credit without noisy fixture-task loops",
                "source": daemon_health_path.name if daemon_health_path else "codex_training_interventions",
            },
            {
                "metric": "TOD Autonomous Daemon Next Action",
                "current": daemon_health_next_action,
                "target": "daemon retry path is bounded and does not inflate TOD progress",
                "source": daemon_health_path.name if daemon_health_path else "codex_training_interventions",
            },
            {
                "metric": "Corrected Patch Synthesis Practice",
                "current": _patch_synthesis_practice_metric(
                    patch_synthesis_practice,
                    patch_synthesis_practice_backup_path,
                    patch_synthesis_practice_backup,
                ),
                "target": "TOD practices current-code Old Text/New Text synthesis or exact unsafe-directive blocking before another independent-resolution attempt",
                "source": PATCH_SYNTHESIS_PRACTICE_PATH.name,
            },
            {
                "metric": "Structural Reasoning Diversity",
                "current": structural_current,
                "target": "90%+ weighted pass without premature closure",
                "source": "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json",
            },
            {
                "metric": "Structural Reasoning Cross-Surface Propagation",
                "current": cross_surface_current,
                "target": "90%+ weighted pass on every MIM-facing surface",
                "source": "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json",
            },
            {
                "metric": "Context-Grounded Conversation",
                "current": context_grounding_current,
                "target": "90%+ weighted pass; replies use current turn, prior turn, page/upload/project context, and evidence boundaries",
                "source": "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json",
            },
            {
                "metric": "Dispatcher State",
                "current": _dispatcher_current(dispatcher, completed_drills),
                "target": "no idle state without successor action",
                "source": "MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
            },
            {
                "metric": "Idle Training State",
                "current": _idle_training_current(idle, completed_drills),
                "target": "training produces real movement or a narrower blocker",
                "source": "TOD_IDLE_TRAINING_STATUS.latest.json",
            },
        ],
        "cycle_001": {
            "status": "ready",
            "actions": [
                {
                    "action": "Score the next 10 live MIM operational replies against the five-field contract.",
                    "owner": "MIM",
                    "evidence": "Updated MIM_OPERATOR_IMPACT_SCORECARD with 10 scored replies and per-field pass rates.",
                    "aging": "Review after 10 replies or 24 hours, whichever comes first.",
                    "dave_needed": "no",
                },
                {
                    "action": "Dispatch one bounded TOD task that must inspect, edit or block with evidence, validate, and publish truth.",
                    "owner": "TOD",
                    "evidence": "Fresh TOD result artifact with changed files or inspected blocker, validation output, and successor state.",
                    "aging": "Escalate if no fresh result appears in the next active cycle.",
                    "dave_needed": "no",
                },
                {
                    "action": "Retire, refresh, or map one stale training artifact to a current project state.",
                    "owner": "MIM + TOD",
                    "evidence": "Stale artifact retirement record naming the artifact, current state, owner, and reason.",
                    "aging": "One stale artifact must move per cycle until the stale count is 0 or source-labeled historical.",
                    "dave_needed": "no",
                },
                {
                    "action": "Select one vague working project and force it into completed, split, dispatched, waiting-with-evidence, blocked-with-owner, or archived.",
                    "owner": "MIM",
                    "evidence": "Project event showing successor or terminal state and expected evidence.",
                    "aging": "Any project with 24 hours of no movement must be reviewed.",
                    "dave_needed": "no unless policy, credential, or external-account approval is required.",
                },
                {
                    "action": "Record whether the cycle moved a project closer to completion.",
                    "owner": "MIM + TOD",
                    "evidence": "Movement outcome label: moved, did_not_move, blocked_with_evidence, split, closed, or archived.",
                    "aging": "Record before the next cycle starts.",
                    "dave_needed": "no",
                },
            ],
        },
        "source_snapshot": {
            "training_scoreboard_generated_at": scoreboard.get("generated_at"),
            "operator_scorecard_generated_at": operator.get("generated_at"),
            "structural_reasoning_generated_at": structural.get("generated_at"),
            "structural_cross_surface_generated_at": cross_surface.get("generated_at"),
            "context_grounding_generated_at": context_grounding.get("generated_at"),
            "dispatcher_generated_at": dispatcher.get("generated_at"),
            "idle_training_generated_at": idle.get("generated_at"),
            "patch_synthesis_practice_generated_at": patch_synthesis_practice.get("generated_at"),
            "patch_synthesis_practice_backup": patch_synthesis_practice_backup_path.name
            if patch_synthesis_practice_backup_path
            else None,
            "blocked_summary": blocked_count,
        },
    }

    _write_json(TRAINING_ROOT / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json", payload)
    _write_md(TRAINING_ROOT / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.md", payload)
    _write_independent_resolution_ladder(
        generated_at=now,
        broader_independent_resolution_count=independent_resolutions_value,
        independent_attempt=independent_attempt,
    )


if __name__ == "__main__":
    main()
