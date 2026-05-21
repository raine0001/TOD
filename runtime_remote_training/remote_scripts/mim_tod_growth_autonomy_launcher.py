#!/usr/bin/env python3
"""Launch the selected MIM/TOD growth objective when the system is idle."""

from __future__ import annotations

import json
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRAINING_DIR = ROOT / "runtime" / "training"
SHARED_DIR = ROOT / "runtime" / "shared"
STATUS_PATH = TRAINING_DIR / "MIM_TOD_GROWTH_AUTONOMY_STATUS.latest.json"
HISTORY_PATH = TRAINING_DIR / "MIM_TOD_GROWTH_AUTONOMY_HISTORY.latest.json"
LAB_AWARENESS_OBJECTIVE_ID = "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1"
LAB_AWARENESS_REQUIRED_ARTIFACTS = (
    "MIM_LAB_AWARENESS_STATUS.latest.json",
    "MIM_LAB_SENSOR_INVENTORY.latest.json",
    "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
    "MIM_HUMAN_INTERACTION_MEMORY.latest.json",
    "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json",
    "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def missing_lab_awareness_artifacts() -> list[str]:
    return [
        artifact
        for artifact in LAB_AWARENESS_REQUIRED_ARTIFACTS
        if not (SHARED_DIR / artifact).is_file()
    ]


def active_operator_incident_blocks_growth() -> bool:
    incident = read_json(SHARED_DIR / "MIM_OPERATOR_INCIDENT.latest.json")
    if incident.get("active") is not True:
        return False
    objective_id = str(incident.get("objective_id") or "").strip()
    if objective_id != LAB_AWARENESS_OBJECTIVE_ID:
        return False
    return bool(missing_lab_awareness_artifacts())


def parse_utc(value: object) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def recent(value: object, window_seconds: int) -> bool:
    parsed = parse_utc(value)
    if parsed is None:
        return False
    return (datetime.now(timezone.utc) - parsed).total_seconds() < window_seconds


def post_to_mim(objective_id: str, domain_id: str) -> dict:
    prompt = f"""OBJECTIVE: {objective_id}

MIM/TOD, this is an autonomous growth-cycle objective selected from MIM_TOD_GROWTH_CYCLE_STATE.latest.json.

Selected domain: {domain_id}

Required behavior:
- run local MIM/TOD diagnosis and probe first
- no Codex-first diagnosis
- no hardware movement
- no broad patch
- produce growth objective result, metrics, and operator summary artifacts
- report completion with evidence, errors=[], tod_errors=[]
"""
    payload = {
        "text": prompt,
        "parsed_intent": "conversation",
        "safety_flags": [],
        "metadata_json": {
            "source": "mim_tod_growth_autonomy_launcher",
            "interaction_mode": "text",
            "message_type": "user",
            "conversation_session_id": f"growth-autonomy-{uuid.uuid4()}",
            "route_preference": "conversation_layer",
        },
    }
    request = urllib.request.Request(
        "http://127.0.0.1:18001/gateway/intake/text",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def objective_for_domain(domain_id: str) -> str:
    return f"MIM-GROWTH-{domain_id.upper().replace('_', '-')}-NEXT-V1"


def recent_completed_from_history(history: dict) -> set[str]:
    entries = history.get("entries") if isinstance(history.get("entries"), list) else []
    completed: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or not entry.get("completed"):
            continue
        if not recent(entry.get("generated_at"), 7 * 24 * 60 * 60):
            continue
        objective_id = str(entry.get("objective_id") or "").strip().upper()
        if objective_id:
            completed.add(objective_id)
    return completed


def recent_completed_domains_from_history(history: dict) -> set[str]:
    entries = history.get("entries") if isinstance(history.get("entries"), list) else []
    completed: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or not entry.get("completed"):
            continue
        if not recent(entry.get("generated_at"), 7 * 24 * 60 * 60):
            continue
        domain_id = str(entry.get("domain_id") or "").strip()
        if domain_id:
            completed.add(domain_id)
    return completed


def recent_completion_times_from_history(history: dict) -> dict[str, datetime]:
    entries = history.get("entries") if isinstance(history.get("entries"), list) else []
    completed: dict[str, datetime] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not entry.get("completed"):
            continue
        objective_id = str(entry.get("objective_id") or "").strip().upper()
        completed_at = parse_utc(entry.get("generated_at"))
        if not objective_id or completed_at is None:
            continue
        previous = completed.get(objective_id)
        if previous is None or completed_at > previous:
            completed[objective_id] = completed_at
    return completed


def choose_next_objective(cycle: dict, latest_result: dict, status: dict, history: dict) -> tuple[str, str, str]:
    selected = cycle.get("selected_next_growth_objective") if isinstance(cycle.get("selected_next_growth_objective"), dict) else {}
    objective_id = str(selected.get("objective_id") or "").strip()
    domain_id = str(selected.get("domain_id") or "").strip()
    latest_objective = str(latest_result.get("objective", {}).get("objective_id") or "").strip()
    latest_completed = latest_result.get("completion_status") == "completed_with_evidence"
    completed_recently = latest_completed and recent(latest_result.get("generated_at"), 24 * 60 * 60)
    completed_objectives = recent_completed_from_history(history)
    completed_domains = recent_completed_domains_from_history(history)
    if latest_completed and completed_recently and latest_objective:
        completed_objectives.add(latest_objective.upper())
        if latest_result.get("objective", {}).get("domain_id"):
            completed_domains.add(str(latest_result.get("objective", {}).get("domain_id")))
    selected_completed_recently = objective_id.upper() in completed_objectives
    scored = cycle.get("scored_domains") if isinstance(cycle.get("scored_domains"), list) else []
    scored_domain_ids = {
        str(item.get("domain_id") or "").strip()
        for item in scored
        if isinstance(item, dict) and str(item.get("domain_id") or "").strip()
    }
    all_domains_exercised_recently = bool(scored_domain_ids) and scored_domain_ids.issubset(completed_domains)
    emergency_override = bool(
        cycle.get("evidence_weighted_emergency_override")
        or cycle.get("emergency_override")
        or status.get("evidence_weighted_emergency_override")
    )
    recent_completion_times = recent_completion_times_from_history(history)
    if latest_completed and completed_recently and latest_objective:
        recent_completion_times[latest_objective.upper()] = parse_utc(latest_result.get("generated_at")) or datetime.now(timezone.utc)

    if objective_id and latest_objective.upper() != objective_id.upper() and (not selected_completed_recently or emergency_override):
        return objective_id, domain_id, "cycle_state_selected_objective"
    if objective_id and not completed_recently and (not selected_completed_recently or emergency_override):
        return objective_id, domain_id, "cycle_state_selected_objective_not_completed_recently"

    sorted_domains = sorted(
        [item for item in scored if isinstance(item, dict) and str(item.get("domain_id") or "").strip()],
        key=lambda item: int(item.get("total_score") or 0),
        reverse=True,
    )
    latest_domain = str(latest_result.get("objective", {}).get("domain_id") or domain_id or "").strip()
    for item in sorted_domains:
        candidate_domain = str(item.get("domain_id") or "").strip()
        candidate_objective = objective_for_domain(candidate_domain)
        if candidate_domain and candidate_domain != latest_domain and candidate_objective.upper() not in completed_objectives:
            return objective_for_domain(candidate_domain), candidate_domain, "advanced_to_next_scored_domain"
    if not all_domains_exercised_recently and not emergency_override:
        for item in sorted_domains:
            candidate_domain = str(item.get("domain_id") or "").strip()
            candidate_objective = objective_for_domain(candidate_domain)
            if candidate_domain and candidate_domain not in completed_domains:
                return candidate_objective, candidate_domain, "growth_diversity_guard_unexercised_domain"
    least_recent_candidate = None
    least_recent_time = None
    for item in sorted_domains:
        candidate_domain = str(item.get("domain_id") or "").strip()
        candidate_objective = objective_for_domain(candidate_domain)
        completed_at = recent_completion_times.get(candidate_objective.upper())
        if not candidate_domain:
            continue
        if completed_at is None:
            return candidate_objective, candidate_domain, "advanced_to_unrecorded_scored_domain"
        if least_recent_time is None or completed_at < least_recent_time:
            least_recent_candidate = (candidate_objective, candidate_domain)
            least_recent_time = completed_at
    if least_recent_candidate:
        reason = "all_scored_domains_completed_recently_rotating_least_recent"
        if emergency_override:
            reason = "evidence_weighted_emergency_override"
        return least_recent_candidate[0], least_recent_candidate[1], reason
    if objective_id:
        return objective_id, domain_id, "only_selected_domain_available"
    return "", "", "no_selected_growth_objective"


def main() -> int:
    now = utc_now()
    cycle = read_json(TRAINING_DIR / "MIM_TOD_GROWTH_CYCLE_STATE.latest.json")
    status = read_json(STATUS_PATH)
    result = read_json(TRAINING_DIR / "MIM_TOD_GROWTH_OBJECTIVE_RESULT.latest.json")
    history = read_json(HISTORY_PATH)
    objective_id, domain_id, selection_reason = choose_next_objective(cycle, result, status, history)
    operator_status = read_json(SHARED_DIR / "MIM_OPERATOR_STATUS.latest.json")
    missing_lab_artifacts = missing_lab_awareness_artifacts()

    base = {
        "packet_type": "mim-tod-growth-autonomy-status-v1",
        "updated_at": now,
        "selected_objective_id": objective_id,
        "selected_domain": domain_id,
        "selection_reason": selection_reason,
        "operator_phase": operator_status.get("current_phase"),
        "operator_objective": operator_status.get("current_objective_id"),
    }
    if missing_lab_artifacts and active_operator_incident_blocks_growth():
        write_json(
            STATUS_PATH,
            {
                **base,
                "state": "skipped",
                "reason": "active_operator_objective_not_idle",
                "blocked_by_objective": LAB_AWARENESS_OBJECTIVE_ID,
                "missing_required_artifacts": missing_lab_artifacts,
                "next_action": "return_to_lab_awareness_objective",
            },
        )
        return 0
    if not objective_id:
        write_json(STATUS_PATH, {**base, "state": "blocked", "reason": "no_selected_growth_objective"})
        return 1
    if (
        status.get("selected_objective_id") == objective_id
        and status.get("state") in {"started", "completed"}
        and recent(status.get("updated_at"), 30 * 60)
    ):
        write_json(STATUS_PATH, {**base, "state": "skipped", "reason": "recent_growth_cycle_already_started"})
        return 0
    write_json(STATUS_PATH, {**base, "state": "starting", "reason": "launching_selected_growth_objective"})
    try:
        parsed = post_to_mim(objective_id, domain_id)
    except Exception as exc:  # noqa: BLE001
        write_json(STATUS_PATH, {**base, "state": "failed", "reason": "gateway_post_failed", "error": str(exc)})
        return 1
    time.sleep(5)
    result = read_json(TRAINING_DIR / "MIM_TOD_GROWTH_OBJECTIVE_RESULT.latest.json")
    completed = (
        result.get("objective", {}).get("objective_id", "").upper() == objective_id.upper()
        and result.get("completion_status") == "completed_with_evidence"
        and result.get("errors") == []
        and result.get("tod_errors") == []
    )
    write_json(
        STATUS_PATH,
        {
            **base,
            "state": "completed" if completed else "started",
            "reason": "growth_objective_completed" if completed else "growth_objective_dispatched_waiting_for_result",
            "mim_reason": (parsed.get("resolution") or {}).get("reason"),
            "mim_reply": ((parsed.get("mim_interface") or {}).get("reply_text") or (parsed.get("resolution") or {}).get("clarification_prompt") or "")[:800],
            "result_artifact_present": bool(result),
        },
    )
    entries = history.get("entries") if isinstance(history.get("entries"), list) else []
    entries.append(
        {
            "generated_at": utc_now(),
            "objective_id": objective_id,
            "domain_id": domain_id,
            "selection_reason": selection_reason,
            "completed": completed,
        }
    )
    write_json(HISTORY_PATH, {"packet_type": "mim-tod-growth-autonomy-history-v1", "updated_at": utc_now(), "entries": entries[-100:]})
    return 0 if completed else 0


if __name__ == "__main__":
    raise SystemExit(main())
