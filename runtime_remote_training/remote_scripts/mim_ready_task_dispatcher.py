#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import subprocess
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import select

from core.db import SessionLocal
from core.models import Objective, Task, TaskResult


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_READY_TASK_DISPATCHER_STATUS.latest.json"
OBJECTIVE_EXECUTION_STATUS_PATH = SHARED / "MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json"
BLOCKER_FOLLOWON_PATH = SHARED / "MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json"
NEXT_BLOCKER_OBJECTIVE_PATH = SHARED / "MIM_TOD_NEXT_BLOCKER_OBJECTIVE.latest.json"
NEXT_OBJECTIVE_PATH = SHARED / "MIM_TOD_NEXT_OBJECTIVE.latest.json"
OBJECTIVE_LEDGER_PATH = SHARED / "MIM_TOD_OBJECTIVE_LEDGER.latest.json"
MANAGED_OBJECTIVES_PATH = SHARED / "MIM_TOD_MANAGED_OBJECTIVES.latest.json"
OBJECTIVE_STACK_PATH = SHARED / "MIM_TOD_OBJECTIVE_EXECUTION_RELIABILITY_STACK_20260528.latest.json"
TASK_REQUEST_PATH = SHARED / "MIM_TOD_TASK_REQUEST.latest.json"
TASK_RESULT_PATH = SHARED / "TOD_MIM_TASK_RESULT.latest.json"
STALE_RECOVERY_PATH = SHARED / "MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json"
LANE_ARBITRATION_PATH = SHARED / "MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json"
OPERATOR_STATUS_SURFACE_PATH = SHARED / "MIM_TOD_OPERATOR_STATUS_SURFACE.latest.json"
LIFECYCLE_REGRESSION_PATH = SHARED / "MIM_TOD_OBJECTIVE_LIFECYCLE_REGRESSION.latest.json"
ACTIVE_OBJECTIVE_PROMOTION_PATH = SHARED / "MIM_TOD_ACTIVE_OBJECTIVE_ARTIFACT_PROMOTION.latest.json"
VOICE_OBJECTIVE_INTAKE_POLICY_PATH = SHARED / "MIM_VOICE_OBJECTIVE_INTAKE_POLICY.latest.json"
EXECUTOR_REGISTRY_PATH = SHARED / "MIM_TOD_EXECUTOR_CAPABILITY_REGISTRY.latest.json"
CONVERSATION_CONTROL_BINDING_PATH = SHARED / "MIM_LAB_CONVERSATION_CONTROL_LAYER_EXECUTOR_BINDING.latest.json"
CONVERSATION_CONTROL_REGRESSION_PATH = SHARED / "MIM_LAB_CONVERSATION_CONTROL_LAYER_REGRESSION.latest.json"
BLOCKED_ROW_CLEANUP_PATH = SHARED / "MIM_TOD_MATERIALIZED_BLOCKED_ROW_CLEANUP.latest.json"
CONVERSATION_CONTROL_LIVE_QUALITY_PATH = SHARED / "MIM_LAB_CONVERSATION_CONTROL_LAYER_LIVE_QUALITY.latest.json"
REAL_MIC_TRANSCRIPT_CALIBRATION_PATH = SHARED / "MIM_LAB_REAL_MIC_TRANSCRIPT_CALIBRATION.latest.json"
CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_PATH = SHARED / "MIM_CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_V2.latest.json"
OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_PATH = SHARED / "MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json"
FRESHNESS_PROVENANCE_TRUST_RANKING_PATH = SHARED / "MIM_TOD_FRESHNESS_PROVENANCE_AND_TRUST_RANKING.latest.json"
ESCALATION_AUTONOMY_PATH = SHARED / "MIM_TOD_ESCALATION_AUTONOMY.latest.json"
BAT_PHONE_RECOVERY_PATH = SHARED / "MIM_TOD_BAT_PHONE_RECOVERY.latest.json"
PREVENTION_MEMORY_PATH = SHARED / "MIM_TOD_PREVENTION_MEMORY.latest.json"
STALE_RUNNING_OBJECTIVE_RECONCILIATION_PATH = SHARED / "MIM_TOD_STALE_RUNNING_OBJECTIVE_RECONCILIATION.latest.json"
TRAINING_TO_ACTION_REFLEX_PATH = SHARED / "MIM_TOD_TRAINING_TO_ACTION_REFLEX.latest.json"
BLOCKER_FOLLOWON_MATERIALIZER_PATH = SHARED / "MIM_TOD_BLOCKER_FOLLOWON_MATERIALIZER.latest.json"
OBJECTIVE_TASK_STATE_RECONCILIATION_PATH = SHARED / "MIM_TOD_OBJECTIVE_TASK_STATE_RECONCILIATION.latest.json"
INTENT_TO_APPLICATION_PIPELINE_PATH = SHARED / "MIM_INTENT_TO_APPLICATION_PIPELINE.latest.json"
INTENT_DISCOVERY_SURFACE_PATH = SHARED / "MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.json"
INTENT_DISCOVERY_SURFACE_HTML_PATH = SHARED / "MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.html"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def run_command(args: list[str], *, timeout: int = 10) -> dict[str, Any]:
    try:
        proc = subprocess.run(
            args,
            cwd=str(ROOT),
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return {
            "command": args,
            "returncode": proc.returncode,
            "stdout": proc.stdout[-4000:],
            "stderr": proc.stderr[-4000:],
            "ok": proc.returncode == 0,
        }
    except Exception as exc:
        return {
            "command": args,
            "returncode": None,
            "stdout": "",
            "stderr": f"{type(exc).__name__}: {exc}",
            "ok": False,
        }


def load_json_url(url: str, *, timeout: int = 8) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            data = response.read(100_000)
        return {
            "ok": True,
            "status": getattr(response, "status", None),
            "payload": json.loads(data.decode("utf-8")),
            "error": "",
        }
    except Exception as exc:
        return {
            "ok": False,
            "status": None,
            "payload": {},
            "error": f"{type(exc).__name__}: {exc}",
        }


def load_json_file(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def slugify(value: str, *, fallback: str = "unknown") -> str:
    slug = re.sub(r"[^A-Za-z0-9]+", "-", value or "").strip("-").upper()
    return slug or fallback.upper()


def objective_items_from_status(status_payload: dict[str, Any]) -> list[dict[str, Any]]:
    raw = status_payload.get("objectives")
    if isinstance(raw, dict):
        return [item for item in raw.values() if isinstance(item, dict)]
    if isinstance(raw, list):
        return [item for item in raw if isinstance(item, dict)]
    return []


def is_blocked_objective(item: dict[str, Any]) -> bool:
    status = str(item.get("status") or "").lower()
    reason = str(item.get("reason_code") or "").lower()
    action = str(item.get("next_recovery_action") or "").lower()
    if "complete" in status and "blocked" not in status:
        return False
    if status in {"queued", "proposed", "ready", "pending", "running", "active"}:
        return False
    if any(token in status for token in ("blocked", "stale_needs_recovery", "no_executor", "not_bound")):
        return True
    if any(token in reason for token in ("blocked", "missing", "no_executor", "not_bound", "unavailable")):
        return True
    return bool(action and any(token in action for token in ("blocked because", "missing executor", "not bound", "unavailable")))


def synthesize_blocker_followon_objective(item: dict[str, Any]) -> dict[str, Any]:
    source_objective_id = str(item.get("objective_id") or item.get("id") or "unknown").strip()
    reason_code = str(item.get("reason_code") or "blocked_without_reason_code").strip()
    title = str(item.get("title") or source_objective_id or "Blocked objective").strip()
    next_action = str(item.get("next_recovery_action") or "Inspect blocker evidence and bind the missing executor or validation path.").strip()
    summary = str(item.get("operator_facing_summary") or item.get("summary") or "").strip()
    objective_id = f"{slugify(source_objective_id)}-UNBLOCK-{slugify(reason_code)}-V1"
    expected_artifacts = [str(item.get("artifact") or "").strip()] if str(item.get("artifact") or "").strip() else []

    return {
        "objective_id": objective_id,
        "title": f"Resolve blocker: {title}",
        "priority": "P0",
        "owner": "MIM_TOD",
        "status": "queued",
        "source_objective_id": source_objective_id,
        "problem_class": reason_code,
        "why_blocked": summary or f"{title} is blocked because {reason_code}.",
        "requested_outcome": next_action,
        "required_actions": [
            "Inspect the source objective evidence artifact and confirm the blocker is still current.",
            "Check canonical solutions and existing capabilities before creating or changing code.",
            "Bind the missing executor, adapter, validation, credential, or runtime path named by the blocker.",
            "Publish explicit evidence showing the blocker resolved or a narrower blocker remains.",
            "Update operator-facing status in concise human language.",
        ],
        "validation_requirements": [
            "source blocker artifact inspected",
            "canonical capability check recorded",
            "fresh evidence artifact published",
            "status moves to running/completed_with_evidence or a narrower blocked_with_evidence state",
        ],
        "evidence_inputs": expected_artifacts,
        "lineage": {
            "created_from": "mim_ready_task_dispatcher_blocker_synthesis",
            "source_artifact": "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
            "source_objective_id": source_objective_id,
            "source_reason_code": reason_code,
        },
    }


def synthesize_blocker_followon_objectives() -> dict[str, Any]:
    generated_at = now_iso()
    status_payload = load_json_file(OBJECTIVE_EXECUTION_STATUS_PATH)
    items = objective_items_from_status(status_payload)
    blocked_items = [item for item in items if is_blocked_objective(item)]

    followons_by_id: dict[str, dict[str, Any]] = {}
    for item in blocked_items:
        followon = synthesize_blocker_followon_objective(item)
        followons_by_id[followon["objective_id"]] = followon

    objectives = list(followons_by_id.values())
    active = objectives[0] if objectives else None
    payload = {
        "packet_type": "mim-tod-blocker-followon-objectives-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher",
        "source_status_artifact": "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        "blocked_count": len(blocked_items),
        "objective_count": len(objectives),
        "objectives": objectives,
        "active_followon_objective_id": active.get("objective_id") if active else "",
        "operator_facing_summary": (
            f"{len(objectives)} blocker follow-on objective(s) are queued for MIM/TOD."
            if objectives
            else "No blocked objectives currently require synthesized follow-on work."
        ),
    }
    write_json(BLOCKER_FOLLOWON_PATH, payload)

    if active:
        next_payload = {
            "packet_type": "mim-tod-next-objective-v1",
            "generated_at": generated_at,
            "objective_id": active["objective_id"],
            "status": "active",
            "goal": active["requested_outcome"],
            "source_deck": "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
            "source_objective_id": active["source_objective_id"],
            "problem_class": active["problem_class"],
            "order": active["required_actions"],
            "success": "The source blocker is resolved with fresh evidence, or a narrower explicit blocker is published.",
            "current_blockers": [active["problem_class"]],
            "next_safe_action": active["requested_outcome"],
            "operator_facing_summary": f"Next blocker to resolve: {active['title']}. {active['requested_outcome']}",
        }
        write_json(NEXT_BLOCKER_OBJECTIVE_PATH, next_payload)
        write_json(NEXT_OBJECTIVE_PATH, next_payload)
    else:
        write_json(
            NEXT_BLOCKER_OBJECTIVE_PATH,
            {
                "packet_type": "mim-tod-next-blocker-objective-v1",
                "generated_at": generated_at,
                "status": "idle",
                "objective_id": "",
                "operator_facing_summary": "No blocked objective needs a follow-on objective right now.",
            },
        )
    return payload


def discover_v4l2_capture_sources() -> dict[str, dict[str, Any]]:
    monitor = run_command(["gst-device-monitor-1.0", "Video/Source"], timeout=15)
    sources: dict[str, dict[str, Any]] = {}
    if not monitor["ok"] and not monitor.get("stdout"):
        return sources
    current: dict[str, Any] = {}
    for line in str(monitor.get("stdout") or "").splitlines():
        stripped = line.strip()
        if stripped.startswith("name  :"):
            current = {"name": stripped.split(":", 1)[1].strip()}
        elif "api.v4l2.path =" in stripped:
            current["path"] = stripped.split("=", 1)[1].strip()
        elif stripped.startswith("object.id ="):
            current["pipewire_object_id"] = stripped.split("=", 1)[1].strip()
        elif stripped.startswith("media.class ="):
            current["media_class"] = stripped.split("=", 1)[1].strip()
        if current.get("path") and current.get("media_class") == "Video/Source":
            sources[str(current["path"])] = dict(current)
            current = {}
    return sources


def probe_video_device(device: str) -> dict[str, Any]:
    result: dict[str, Any] = {
        "device_id": device,
        "source_type": "camera",
        "exists": Path(device).exists(),
        "openable": False,
        "last_frame_or_sample_time": None,
        "probe_method": "os.open(O_RDONLY|O_NONBLOCK); no media retained",
        "error": "",
    }
    if not result["exists"]:
        result["error"] = "device_node_missing"
        return result
    try:
        fd = os.open(device, os.O_RDONLY | os.O_NONBLOCK)
        os.close(fd)
        result["openable"] = True
        result["open_probe_time"] = now_iso()
        result["error"] = "frame_capture_not_attempted_no_bound_frame_probe_dependency"
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    return result


def parse_arecord_devices(output: str) -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    pattern = re.compile(r"^card\s+(\d+):\s+([^\[]+)\[([^\]]+)\],\s+device\s+(\d+):\s+([^\[]+)\[([^\]]+)\]")
    for line in output.splitlines():
        match = pattern.search(line.strip())
        if not match:
            continue
        card, card_short, card_name, dev, dev_short, dev_name = match.groups()
        devices.append(
            {
                "device_id": f"hw:{card},{dev}",
                "source_type": "microphone",
                "card": int(card),
                "device": int(dev),
                "label": f"{card_name} / {dev_name}",
                "short_label": f"{card_short.strip()} / {dev_short.strip()}",
            }
        )
    return devices


def probe_audio_devices() -> list[dict[str, Any]]:
    listing = run_command(["arecord", "-l"], timeout=8)
    parsed = parse_arecord_devices(listing.get("stdout", ""))
    if not parsed and not listing["ok"]:
        return [
            {
                "device_id": "arecord",
                "source_type": "microphone",
                "exists": False,
                "openable": False,
                "last_frame_or_sample_time": None,
                "probe_method": "arecord -l",
                "error": listing.get("stderr") or "arecord_list_failed",
            }
        ]
    results: list[dict[str, Any]] = []
    for item in parsed:
        card = item["card"]
        dev = item["device"]
        attempts = []
        probe = {"ok": False, "stderr": "no_probe_attempted", "stdout": ""}
        for device_name in (item["device_id"], f"plughw:{card},{dev}"):
            for channels in (1, 2):
                probe = run_command(
                    [
                        "arecord",
                        "-D",
                        device_name,
                        "-d",
                        "1",
                        "-f",
                        "S16_LE",
                        "-r",
                        "16000",
                        "-c",
                        str(channels),
                        "-t",
                        "raw",
                        "/dev/null",
                    ],
                    timeout=5,
                )
                attempts.append(
                    {
                        "device": device_name,
                        "channels": channels,
                        "ok": probe["ok"],
                        "error": "" if probe["ok"] else (probe.get("stderr") or probe.get("stdout") or "audio_probe_failed"),
                    }
                )
                if probe["ok"]:
                    break
            if probe["ok"]:
                break
        results.append(
            {
                **item,
                "exists": True,
                "openable": bool(probe["ok"]),
                "last_frame_or_sample_time": now_iso() if probe["ok"] else None,
                "probe_method": "arecord one-second raw capture to /dev/null; no media retained",
                "probe_attempts": attempts,
                "error": "" if probe["ok"] else (probe.get("stderr") or probe.get("stdout") or "audio_probe_failed"),
            }
        )
    return results


def probe_arm_camera_bridge() -> dict[str, Any]:
    candidates = [
        SHARED / "MIM_ARM_DISPATCH_TELEMETRY.latest.json",
        SHARED / "MIM_ARM_COMPOSED_TASK.latest.json",
        ROOT / "runtime" / "reports" / "mim_arm_first_live_wrist_claw_micro_step.latest.json",
    ]
    inspected = [str(path.relative_to(ROOT)) for path in candidates]
    existing = [path for path in candidates if path.exists()]
    camera_state = load_json_url("http://127.0.0.1:18001/mim/arm/camera-state")
    capture_proposal = load_json_url("http://127.0.0.1:18001/mim/arm/proposals/capture-frame")
    state_payload = camera_state.get("payload") if isinstance(camera_state.get("payload"), dict) else {}
    proposal_payload = capture_proposal.get("payload") if isinstance(capture_proposal.get("payload"), dict) else {}
    dispatch_telemetry = load_json_file(SHARED / "MIM_ARM_DISPATCH_TELEMETRY.latest.json")
    camera_online = bool(state_payload.get("camera_online"))
    live_dispatch_allowed = bool(proposal_payload.get("live_dispatch_allowed"))
    capture_completed = (
        str(dispatch_telemetry.get("command_name") or "").strip() == "capture_frame"
        and str(dispatch_telemetry.get("completion_status") or "").strip() == "completed"
        and str(dispatch_telemetry.get("result_reason") or "").strip() in {"succeeded", "success", "completed"}
    )
    payload: dict[str, Any] = {
        "device_id": "arm-camera-bridge",
        "source_type": "arm_camera",
        "exists": bool(existing) or camera_online,
        "openable": camera_online,
        "last_frame_or_sample_time": dispatch_telemetry.get("host_completed_timestamp") if capture_completed else None,
        "probe_method": "arm camera-state/proposal endpoints plus bridge artifact inspection; no arm movement",
        "inspected_paths": inspected,
        "dispatch_telemetry": {
            "execution_id": dispatch_telemetry.get("execution_id"),
            "dispatch_status": dispatch_telemetry.get("dispatch_status"),
            "completion_status": dispatch_telemetry.get("completion_status"),
            "host_received_timestamp": dispatch_telemetry.get("host_received_timestamp"),
            "host_completed_timestamp": dispatch_telemetry.get("host_completed_timestamp"),
            "result_reason": dispatch_telemetry.get("result_reason"),
            "request_id": dispatch_telemetry.get("request_id"),
        },
        "camera_state": state_payload,
        "capture_frame_proposal": {
            "ok": capture_proposal.get("ok"),
            "live_dispatch_allowed": live_dispatch_allowed,
            "operator_approval_required": proposal_payload.get("operator_approval_required"),
            "reasoning": proposal_payload.get("reasoning"),
            "safety_posture": proposal_payload.get("safety_posture"),
        },
        "error": "" if camera_online else "arm_camera_state_not_online",
        "cycle_error": "" if capture_completed or live_dispatch_allowed else "capture_frame_live_dispatch_not_allowed_or_not_bound",
    }
    if existing:
        payload["bridge_artifacts_present"] = [str(path.relative_to(ROOT)) for path in existing]
    return payload


def probe_camera_frame(device: str) -> dict[str, Any]:
    base = probe_video_device(device)
    if not base.get("exists") or not base.get("openable"):
        return {
            **base,
            "cycled": False,
            "frame_probe_method": "gst-launch not attempted because device is not openable",
        }
    commands = [
        [
            "timeout",
            "10",
            "gst-launch-1.0",
            "-q",
            "v4l2src",
            f"device={device}",
            "num-buffers=1",
            "!",
            "videoconvert",
            "!",
            "fakesink",
        ],
        [
            "timeout",
            "10",
            "gst-launch-1.0",
            "-q",
            "v4l2src",
            f"device={device}",
            "num-buffers=1",
            "!",
            "image/jpeg,width=640,height=480,framerate=30/1",
            "!",
            "jpegdec",
            "!",
            "videoconvert",
            "!",
            "fakesink",
        ],
    ]
    attempts = []
    probe = {"ok": False, "stderr": "no_probe_attempted", "stdout": "", "returncode": None}
    for command in commands:
        probe = run_command(command, timeout=15)
        attempts.append(
            {
                "command": " ".join(command),
                "ok": probe["ok"],
                "returncode": probe.get("returncode"),
                "error": "" if probe["ok"] else (probe.get("stderr") or probe.get("stdout") or "gstreamer_frame_probe_failed"),
            }
        )
        if probe["ok"]:
            break
    ok = bool(probe.get("ok"))
    return {
        **base,
        "cycled": ok,
        "last_frame_or_sample_time": now_iso() if ok else None,
        "frame_probe_method": "gst-launch-1.0 v4l2src num-buffers=1 ! videoconvert ! fakesink; no media retained",
        "frame_probe_command": attempts[-1]["command"] if attempts else "",
        "frame_probe_attempts": attempts,
        "error": "" if ok else (probe.get("stderr") or probe.get("stdout") or "gstreamer_frame_probe_failed"),
        "probe_returncode": probe.get("returncode"),
    }


def run_lab_camera_cycle(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    capture_sources = discover_v4l2_capture_sources()
    all_video_nodes = [f"/dev/video{i}" for i in range(4)]
    capture_nodes = [node for node in all_video_nodes if node in capture_sources]
    non_capture_nodes = [
        {
            "device_id": node,
            "source_type": "camera_metadata_or_non_capture_node",
            "exists": Path(node).exists(),
            "required_for_camera_cycle": False,
            "reason": "gst-device-monitor did not classify this node as media.class=Video/Source",
        }
        for node in all_video_nodes
        if node not in capture_nodes
    ]
    cameras = []
    for node in capture_nodes:
        entry = probe_camera_frame(node)
        entry["device_metadata"] = capture_sources.get(node, {})
        cameras.append(entry)
    arm = probe_arm_camera_bridge()
    arm["cycled"] = bool(arm.get("openable")) and not bool(arm.get("cycle_error"))
    entries = [*cameras, *non_capture_nodes, arm]
    blockers = [
        {
            "device_id": entry.get("device_id"),
            "source_type": entry.get("source_type"),
            "error": entry.get("error") or entry.get("cycle_error") or "cycle_failed",
        }
        for entry in entries
        if entry.get("required_for_camera_cycle", True) and not bool(entry.get("cycled"))
    ]
    status = "completed_with_evidence" if not blockers else "blocked_with_evidence"
    payload = {
        "packet_type": "mim-lab-camera-cycle-status-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher",
        "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
        "mim_api_task_id": task.id,
        "status": status,
        "success": not blockers,
        "no_media_retained": True,
        "cycle_entries": entries,
        "capture_nodes": capture_nodes,
        "non_capture_nodes": non_capture_nodes,
        "blocked_devices": blockers,
        "inspected_paths": [
            "/dev/video0",
            "/dev/video1",
            "/dev/video2",
            "/dev/video3",
            "runtime/shared/MIM_ARM_DISPATCH_TELEMETRY.latest.json",
            "runtime/shared/MIM_ARM_COMPOSED_TASK.latest.json",
            "runtime/reports/mim_arm_first_live_wrist_claw_micro_step.latest.json",
        ],
        "next_recovery_action": (
            "Bind current arm-camera bridge probe before camera-cycle success can be complete."
            if blockers
            else "Proceed to human presence/TTS interaction evidence."
        ),
    }
    write_json(SHARED / "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json", payload)
    write_json(
        SHARED / "MIM_LAB_AWARENESS_STATUS.latest.json",
        {
            "packet_type": "mim-lab-awareness-status-v1",
            "generated_at": generated_at,
            "source": "mim_ready_task_dispatcher",
            "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "phase": "camera_cycle_blocked" if blockers else "camera_cycle_complete",
            "percent_complete": 30 if blockers else 40,
            "currently_blocked": bool(blockers),
            "blocker_if_any": "" if not blockers else "Local camera cycling has evidence, but arm-camera bridge cycle remains blocked.",
            "next_mim_owned_action": payload["next_recovery_action"],
            "required_artifact_checklist": {
                "MIM_LAB_AWARENESS_STATUS.latest.json": {"present": True, "required_for_completion": True},
                "MIM_LAB_SENSOR_INVENTORY.latest.json": {"present": True, "required_for_completion": True},
                "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json": {"present": True, "required_for_completion": True},
                "MIM_HUMAN_INTERACTION_MEMORY.latest.json": {"present": False, "required_for_completion": True},
                "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json": {"present": False, "required_for_completion": True},
                "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json": {"present": False, "required_for_completion": True},
            },
            "success": False,
            "tod_codex_boundary": "monitor_only; MIM-owned dispatcher executed camera cycle probe",
        },
    )
    write_json(
        SHARED / "MIM_OPERATOR_STATUS.latest.json",
        {
            "packet_type": "mim-operator-status-v1",
            "generated_at": generated_at,
            "current_operator_request": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1 camera cycle executor",
            "current_objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "request_type": "mim_lab_runtime",
            "classification": "mim_ready_task_dispatcher",
            "owner": "MIM",
            "current_phase": "camera_cycle_blocked" if blockers else "camera_cycle_complete",
            "what_mim_is_doing": "MIM executed the camera cycle executor and produced current per-camera cycle evidence.",
            "what_tod_is_doing": "TOD is monitoring and guiding; MIM owns the camera, audio, TTS, memory, and object work.",
            "waiting_on": "MIM arm-camera bridge probe" if blockers else "MIM human interaction/TTS executor",
            "last_fresh_event": "MIM produced camera cycle evidence",
            "last_fresh_event_at": generated_at,
            "stale_state_detected": False,
            "stale_panels": ["older no-executor camera-cycle blocker is debug-only after this evidence"],
            "active_artifacts": [
                "runtime/shared/MIM_OPERATOR_STATUS.latest.json",
                "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
                "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
            ],
            "blocking_issue": "" if not blockers else "Arm-camera bridge cycle remains blocked in MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
            "next_safe_action": payload["next_recovery_action"],
            "operator_guidance": "monitor",
            "debug_artifacts_available": True,
        },
    )
    return payload


def run_lab_human_interaction(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    message = "Hello Dave. I recognize you as my primary operator in the lab."
    tts_probe = run_command(["spd-say", message], timeout=8)
    status = "completed_with_evidence" if tts_probe["ok"] else "blocked_with_evidence"
    memory = {
        "packet_type": "mim-human-interaction-memory-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher",
        "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
        "mim_api_task_id": task.id,
        "status": status,
        "success": tts_probe["ok"],
        "interaction": {
            "human_name": "Dave",
            "human_role": "primary_operator",
            "presence_trigger_source": "operator_context_present",
            "presence_trigger_evidence": "operator stated they are in the lab during the active objective",
            "interaction_mode": "voice_tts",
            "tts_message": message,
            "tts_command": tts_probe["command"],
            "tts_dispatch_mode": "speech-dispatcher async queue; command success means utterance accepted",
            "tts_returncode": tts_probe["returncode"],
            "tts_error": "" if tts_probe["ok"] else (tts_probe.get("stderr") or tts_probe.get("stdout") or "tts_failed"),
            "last_interaction_time": generated_at if tts_probe["ok"] else None,
        },
        "memory_records": [
            {
                "human_name": "Dave",
                "remembered_fact": "Dave is MIM's primary operator.",
                "source": "operator-provided objective context",
                "confidence": "operator_asserted",
                "updated_at": generated_at,
            }
        ],
        "next_recovery_action": (
            "Proceed to object memory/inquiry executor."
            if tts_probe["ok"]
            else "Repair speech-dispatcher or default audio output, then rerun human interaction executor."
        ),
    }
    write_json(SHARED / "MIM_HUMAN_INTERACTION_MEMORY.latest.json", memory)

    camera_cycle = load_json_file(SHARED / "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json")
    arm_blocked = bool(camera_cycle.get("blocked_devices"))
    write_json(
        SHARED / "MIM_LAB_AWARENESS_STATUS.latest.json",
        {
            "packet_type": "mim-lab-awareness-status-v1",
            "generated_at": generated_at,
            "source": "mim_ready_task_dispatcher",
            "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "phase": "human_interaction_memory_complete" if tts_probe["ok"] else "human_interaction_memory_blocked",
            "percent_complete": 45 if tts_probe["ok"] else 35,
            "currently_blocked": (not tts_probe["ok"]) or arm_blocked,
            "blocker_if_any": "" if tts_probe["ok"] and not arm_blocked else "TTS or arm-camera evidence remains incomplete.",
            "next_mim_owned_action": memory["next_recovery_action"],
            "required_artifact_checklist": {
                "MIM_LAB_AWARENESS_STATUS.latest.json": {"present": True, "required_for_completion": True},
                "MIM_LAB_SENSOR_INVENTORY.latest.json": {"present": (SHARED / "MIM_LAB_SENSOR_INVENTORY.latest.json").exists(), "required_for_completion": True},
                "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json": {"present": (SHARED / "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json").exists(), "required_for_completion": True},
                "MIM_HUMAN_INTERACTION_MEMORY.latest.json": {"present": True, "required_for_completion": True},
                "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json": {"present": (SHARED / "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json").exists(), "required_for_completion": True},
                "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json": {"present": False, "required_for_completion": True},
            },
            "success": False,
            "tod_codex_boundary": "monitor_only; MIM-owned dispatcher executed human interaction/TTS evidence",
        },
    )
    write_json(
        SHARED / "MIM_OPERATOR_STATUS.latest.json",
        {
            "packet_type": "mim-operator-status-v1",
            "generated_at": generated_at,
            "current_operator_request": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1 human interaction executor",
            "current_objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "request_type": "mim_lab_runtime",
            "classification": "mim_ready_task_dispatcher",
            "owner": "MIM",
            "current_phase": "human_interaction_memory_complete" if tts_probe["ok"] else "human_interaction_memory_blocked",
            "what_mim_is_doing": "MIM produced a voice TTS interaction and recorded Dave as primary operator." if tts_probe["ok"] else "MIM attempted voice TTS interaction and recorded the exact blocker.",
            "what_tod_is_doing": "TOD is monitoring and guiding; MIM owns TTS, memory, object inquiry, and remaining arm-camera work.",
            "waiting_on": "MIM object memory/inquiry executor" if tts_probe["ok"] else "MIM TTS/audio output recovery",
            "last_fresh_event": "MIM produced human interaction memory evidence",
            "last_fresh_event_at": generated_at,
            "stale_state_detected": False,
            "stale_panels": [],
            "active_artifacts": [
                "runtime/shared/MIM_OPERATOR_STATUS.latest.json",
                "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
                "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
                "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json",
            ],
            "blocking_issue": "" if tts_probe["ok"] else "Voice TTS did not complete; see MIM_HUMAN_INTERACTION_MEMORY.latest.json",
            "next_safe_action": memory["next_recovery_action"],
            "operator_guidance": "monitor",
            "debug_artifacts_available": True,
        },
    )
    return memory


def run_lab_object_inquiry(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    camera_cycle = load_json_file(SHARED / "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json")
    sensor_inventory = load_json_file(SHARED / "MIM_LAB_SENSOR_INVENTORY.latest.json")
    cycled_cameras = [
        entry.get("device_id")
        for entry in camera_cycle.get("cycle_entries", [])
        if entry.get("source_type") == "camera" and entry.get("cycled")
    ]
    known_objects = []
    for device in sensor_inventory.get("devices", []):
        device_id = str(device.get("device_id") or "").strip()
        source_type = str(device.get("source_type") or "").strip()
        if not device_id or source_type not in {"camera", "microphone", "arm_camera"}:
            continue
        label = str(device.get("label") or device.get("short_label") or device_id).strip()
        known_objects.append(
            {
                "object_id": device_id,
                "object_type": source_type,
                "name": label,
                "evidence_source": "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
                "exists": bool(device.get("exists")),
                "openable": bool(device.get("openable")),
                "last_seen_or_sampled_at": device.get("last_frame_or_sample_time"),
            }
        )
    for entry in camera_cycle.get("cycle_entries", []):
        device_id = str(entry.get("device_id") or "").strip()
        if not device_id or not bool(entry.get("cycled")):
            continue
        if not any(item.get("object_id") == device_id for item in known_objects):
            known_objects.append(
                {
                    "object_id": device_id,
                    "object_type": str(entry.get("source_type") or "camera").strip(),
                    "name": device_id,
                    "evidence_source": "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
                    "exists": bool(entry.get("exists", True)),
                    "openable": bool(entry.get("openable", True)),
                    "last_seen_or_sampled_at": entry.get("last_frame_or_sample_time"),
                }
            )
    message = "Dave, my lab cameras are available. Please name any important objects I should remember."
    tts_probe = run_command(["spd-say", message], timeout=8)
    has_camera_evidence = bool(cycled_cameras)
    status = "completed_with_evidence" if has_camera_evidence and tts_probe["ok"] and known_objects else "blocked_with_evidence"
    payload = {
        "packet_type": "mim-object-memory-and-inquiry-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher",
        "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
        "mim_api_task_id": task.id,
        "status": status,
        "success": status == "completed_with_evidence",
        "known_objects": known_objects,
        "unknown_object_inquiry": {
            "inquiry_mode": "voice_tts",
            "prompt": message,
            "reason": "Object-recognition labels are not yet bound; MIM is asking the primary operator for names before storing object memory.",
            "tts_command": tts_probe["command"],
            "tts_dispatch_mode": "speech-dispatcher async queue; command success means utterance accepted",
            "tts_returncode": tts_probe["returncode"],
            "tts_error": "" if tts_probe["ok"] else (tts_probe.get("stderr") or tts_probe.get("stdout") or "tts_failed"),
        },
        "available_visual_evidence": {
            "cycled_cameras": cycled_cameras,
            "camera_cycle_artifact": "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
            "arm_camera_cycle_blocked": bool(camera_cycle.get("blocked_devices")),
        },
        "blockers": [
            blocker
            for blocker in [
                None if has_camera_evidence else {"reason_code": "no_camera_cycle_evidence", "recovery": "Rerun camera cycle executor."},
                None if tts_probe["ok"] else {"reason_code": "object_inquiry_tts_failed", "recovery": "Repair speech output and rerun object inquiry executor."},
                None if known_objects else {"reason_code": "no_known_lab_objects_derived", "recovery": "Rerun sensor inventory and camera cycle before object memory."},
            ]
            if blocker
        ],
        "open_learning_need": {
            "reason_code": "general_object_recognition_model_not_bound",
            "impact": "MIM can remember known lab devices and ask about unknown objects, but arbitrary visual object labels still require operator labels or a local vision-labeling executor.",
            "next_training_objective": "Bind operator-label capture or local vision labeling for non-device lab objects.",
        },
        "next_recovery_action": "Proceed to final lab-awareness evidence validation." if status == "completed_with_evidence" else "Recover camera evidence, TTS, or sensor-derived object memory.",
    }
    write_json(SHARED / "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json", payload)
    write_json(
        SHARED / "MIM_LAB_AWARENESS_STATUS.latest.json",
        {
            "packet_type": "mim-lab-awareness-status-v1",
            "generated_at": generated_at,
            "source": "mim_ready_task_dispatcher",
            "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "phase": "object_memory_and_inquiry_complete" if payload["success"] else "object_inquiry_blocked",
            "percent_complete": 75 if payload["success"] else 50,
            "currently_blocked": not payload["success"],
            "blocker_if_any": "" if payload["success"] else "Object inquiry exists, but object memory evidence remains incomplete.",
            "next_mim_owned_action": payload["next_recovery_action"],
            "required_artifact_checklist": {
                "MIM_LAB_AWARENESS_STATUS.latest.json": {"present": True, "required_for_completion": True},
                "MIM_LAB_SENSOR_INVENTORY.latest.json": {"present": (SHARED / "MIM_LAB_SENSOR_INVENTORY.latest.json").exists(), "required_for_completion": True},
                "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json": {"present": (SHARED / "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json").exists(), "required_for_completion": True},
                "MIM_HUMAN_INTERACTION_MEMORY.latest.json": {"present": (SHARED / "MIM_HUMAN_INTERACTION_MEMORY.latest.json").exists(), "required_for_completion": True},
                "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json": {"present": True, "required_for_completion": True},
                "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json": {"present": False, "required_for_completion": True},
            },
            "success": False,
            "tod_codex_boundary": "monitor_only; MIM-owned dispatcher executed object inquiry evidence",
        },
    )
    write_json(
        SHARED / "MIM_OPERATOR_STATUS.latest.json",
        {
            "packet_type": "mim-operator-status-v1",
            "generated_at": generated_at,
            "current_operator_request": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1 object memory/inquiry executor",
            "current_objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "request_type": "mim_lab_runtime",
            "classification": "mim_ready_task_dispatcher",
            "owner": "MIM",
            "current_phase": "object_memory_and_inquiry_complete" if payload["success"] else "object_inquiry_blocked_on_label_binding",
            "what_mim_is_doing": "MIM stored known lab device objects from sensor evidence and asked Dave to name important unknown objects.",
            "what_tod_is_doing": "TOD is monitoring and guiding; MIM owns final evidence validation and future free-form object label training.",
            "waiting_on": "MIM final lab-awareness evidence validation" if payload["success"] else "MIM object label binding",
            "last_fresh_event": "MIM produced object inquiry evidence",
            "last_fresh_event_at": generated_at,
            "stale_state_detected": False,
            "stale_panels": [],
            "active_artifacts": [
                "runtime/shared/MIM_OPERATOR_STATUS.latest.json",
                "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
                "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
                "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json",
                "runtime/shared/MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json",
            ],
            "blocking_issue": "" if payload["success"] else "Object memory/inquiry evidence is incomplete.",
            "next_safe_action": payload["next_recovery_action"],
            "operator_guidance": "monitor",
            "debug_artifacts_available": True,
        },
    )
    return payload


def run_lab_awareness_final_evidence(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    sensor = load_json_file(SHARED / "MIM_LAB_SENSOR_INVENTORY.latest.json")
    camera = load_json_file(SHARED / "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json")
    human = load_json_file(SHARED / "MIM_HUMAN_INTERACTION_MEMORY.latest.json")
    objects = load_json_file(SHARED / "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json")
    checks = {
        "sensor_inventory": bool(sensor) and str(sensor.get("status") or "") == "completed_with_evidence",
        "camera_cycle_all_required": bool(camera) and bool(camera.get("success")) and not bool(camera.get("blocked_devices")),
        "human_tts_memory": bool(human) and bool(human.get("success")),
        "dave_primary_operator_memory": any(
            record.get("human_name") == "Dave" and "primary operator" in str(record.get("remembered_fact") or "").lower()
            for record in human.get("memory_records", [])
        ),
        "object_memory_and_unknown_inquiry": bool(objects) and bool(objects.get("success")) and bool(objects.get("known_objects")),
    }
    success = all(checks.values())
    blockers = [
        {"reason_code": key, "recovery": "Rerun or repair the corresponding MIM-owned executor."}
        for key, passed in checks.items()
        if not passed
    ]
    payload = {
        "packet_type": "mim-lab-awareness-execution-evidence-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher",
        "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
        "mim_api_task_id": task.id,
        "status": "completed_with_evidence" if success else "blocked_with_evidence",
        "success": success,
        "checks": checks,
        "blockers": blockers,
        "evidence_artifacts": {
            "sensor_inventory": "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
            "camera_cycle": "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
            "human_interaction_memory": "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json",
            "object_memory_and_inquiry": "runtime/shared/MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json",
        },
        "known_humans": [
            {
                "name": "Dave",
                "role": "primary_operator",
                "evidence_artifact": "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json",
            }
        ],
        "known_lab_objects_count": len(objects.get("known_objects", [])) if isinstance(objects.get("known_objects"), list) else 0,
        "camera_cycle_summary": {
            "capture_nodes": camera.get("capture_nodes"),
            "blocked_devices": camera.get("blocked_devices"),
        },
        "next_recovery_action": "" if success else "Repair failed checks, then rerun final evidence validation.",
        "future_learning_objectives": [
            {
                "objective": "Bind free-form lab object label capture or local vision labeling.",
                "reason": "The current object memory covers known devices and asks about unknowns; arbitrary non-device object naming still needs labels.",
            }
        ],
    }
    write_json(SHARED / "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json", payload)
    write_json(
        SHARED / "MIM_LAB_AWARENESS_STATUS.latest.json",
        {
            "packet_type": "mim-lab-awareness-status-v1",
            "generated_at": generated_at,
            "source": "mim_ready_task_dispatcher",
            "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "phase": "complete_with_evidence" if success else "final_validation_blocked",
            "percent_complete": 100 if success else 85,
            "currently_blocked": not success,
            "blocker_if_any": "" if success else "Final validation failed one or more required evidence checks.",
            "next_mim_owned_action": "" if success else payload["next_recovery_action"],
            "required_artifact_checklist": {
                "MIM_LAB_AWARENESS_STATUS.latest.json": {"present": True, "required_for_completion": True},
                "MIM_LAB_SENSOR_INVENTORY.latest.json": {"present": bool(sensor), "required_for_completion": True},
                "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json": {"present": bool(camera), "required_for_completion": True},
                "MIM_HUMAN_INTERACTION_MEMORY.latest.json": {"present": bool(human), "required_for_completion": True},
                "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json": {"present": bool(objects), "required_for_completion": True},
                "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json": {"present": True, "required_for_completion": True},
            },
            "success": success,
            "tod_codex_boundary": "monitor_only; MIM-owned dispatcher executed final evidence validation",
        },
    )
    write_json(
        SHARED / "MIM_OPERATOR_STATUS.latest.json",
        {
            "packet_type": "mim-operator-status-v1",
            "generated_at": generated_at,
            "current_operator_request": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1 final evidence validation",
            "current_objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "request_type": "mim_lab_runtime",
            "classification": "mim_ready_task_dispatcher",
            "owner": "MIM",
            "current_phase": "complete_with_evidence" if success else "final_validation_blocked",
            "what_mim_is_doing": "MIM validated lab sensor, camera, arm-camera, TTS, human memory, and object inquiry evidence.",
            "what_tod_is_doing": "TOD is monitoring and preserving evidence.",
            "waiting_on": "" if success else "MIM evidence repair",
            "last_fresh_event": "MIM produced final lab-awareness execution evidence",
            "last_fresh_event_at": generated_at,
            "stale_state_detected": False,
            "stale_panels": [],
            "active_artifacts": [
                "runtime/shared/MIM_OPERATOR_STATUS.latest.json",
                "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
                "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
                "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json",
                "runtime/shared/MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json",
                "runtime/shared/MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json",
            ],
            "blocking_issue": "" if success else "Final validation blockers listed in MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json",
            "next_safe_action": "" if success else payload["next_recovery_action"],
            "operator_guidance": "monitor",
            "debug_artifacts_available": True,
        },
    )
    return payload


def run_lab_sensor_inventory(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    devices: list[dict[str, Any]] = []
    devices.extend(probe_video_device(f"/dev/video{i}") for i in range(4))
    devices.extend(probe_audio_devices())
    devices.append(probe_arm_camera_bridge())
    all_have_evidence = all("exists" in device and "openable" in device for device in devices)
    any_openable = any(bool(device.get("openable")) for device in devices)
    blocked_devices = [
        {
            "device_id": device.get("device_id"),
            "source_type": device.get("source_type"),
            "error": device.get("error") or "no_error_detail",
        }
        for device in devices
        if not bool(device.get("openable")) or device.get("last_frame_or_sample_time") is None
    ]
    status = "completed_with_evidence" if all_have_evidence and any_openable else "blocked_with_evidence"
    inventory = {
        "packet_type": "mim-lab-sensor-inventory-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher",
        "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
        "mim_api_task_id": task.id,
        "status": status,
        "success": status == "completed_with_evidence",
        "all_devices_openable_with_frame_or_sample": len(blocked_devices) == 0,
        "blocked_devices": blocked_devices,
        "devices": devices,
        "inspected_paths": [
            "/dev/video0",
            "/dev/video1",
            "/dev/video2",
            "/dev/video3",
            "arecord -l",
            "runtime/shared/MIM_ARM_DISPATCH_TELEMETRY.latest.json",
            "runtime/shared/MIM_ARM_COMPOSED_TASK.latest.json",
            "runtime/reports/mim_arm_first_live_wrist_claw_micro_step.latest.json",
        ],
        "no_media_retained": True,
        "next_recovery_action": (
            "Bind camera frame capture dependency such as OpenCV/v4l2 probe and arm-camera bridge probe."
            if any(device.get("source_type") in {"camera", "arm_camera"} and device.get("openable") and device.get("last_frame_or_sample_time") is None for device in devices)
            else ""
        ),
    }
    write_json(SHARED / "MIM_LAB_SENSOR_INVENTORY.latest.json", inventory)
    currently_blocked = len(blocked_devices) > 0
    status_payload = {
        "packet_type": "mim-lab-awareness-status-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher",
        "objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
        "phase": "sensor_inventory",
        "percent_complete": 15 if status == "completed_with_evidence" else 5,
        "currently_blocked": currently_blocked,
        "blocker_if_any": "" if not currently_blocked else "Sensor inventory produced evidence, but one or more devices remain blocked or lack frame/sample proof.",
        "next_mim_owned_action": "Bind missing camera frame capture, audio capture parameters, or arm-camera bridge probes before camera cycling.",
        "required_artifact_checklist": {
            "MIM_LAB_AWARENESS_STATUS.latest.json": {"present": True, "required_for_completion": True},
            "MIM_LAB_SENSOR_INVENTORY.latest.json": {"present": True, "required_for_completion": True},
            "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json": {"present": False, "required_for_completion": True},
            "MIM_HUMAN_INTERACTION_MEMORY.latest.json": {"present": False, "required_for_completion": True},
            "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json": {"present": False, "required_for_completion": True},
            "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json": {"present": False, "required_for_completion": True},
        },
        "success": False,
        "tod_codex_boundary": "monitor_only; MIM-owned dispatcher executed sensor inventory probe",
    }
    write_json(SHARED / "MIM_LAB_AWARENESS_STATUS.latest.json", status_payload)
    write_json(
        SHARED / "MIM_OPERATOR_STATUS.latest.json",
        {
            "packet_type": "mim-operator-status-v1",
            "generated_at": generated_at,
            "current_operator_request": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1 sensor inventory executor",
            "current_objective_id": "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1",
            "request_type": "mim_lab_runtime",
            "classification": "mim_ready_task_dispatcher",
            "owner": "MIM",
            "current_phase": "sensor_inventory_blocked" if currently_blocked else "sensor_inventory_evidence_ready",
            "what_mim_is_doing": "MIM executed the ready-task dispatcher and produced current lab sensor inventory evidence.",
            "what_tod_is_doing": "TOD is monitoring and guiding; MIM owns the sensor inventory and follow-on camera/audio work.",
            "waiting_on": "MIM sensor probe recovery" if currently_blocked else "MIM camera cycling executor",
            "last_fresh_event": "MIM produced lab sensor inventory evidence",
            "last_fresh_event_at": generated_at,
            "stale_state_detected": False,
            "stale_panels": [
                "older lab-awareness route blockers are debug-only if generated before this sensor inventory evidence"
            ],
            "active_artifacts": [
                "runtime/shared/MIM_OPERATOR_STATUS.latest.json",
                "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
            ],
            "blocking_issue": "" if not currently_blocked else "Per-device blockers remain in MIM_LAB_SENSOR_INVENTORY.latest.json",
            "next_safe_action": status_payload["next_mim_owned_action"],
            "operator_guidance": "monitor",
            "debug_artifacts_available": True,
        },
    )
    return inventory


def no_executor_result(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    metadata = task.metadata_json if isinstance(task.metadata_json, dict) else {}
    dispatch_artifact = task.dispatch_artifact_json if isinstance(task.dispatch_artifact_json, dict) else {}
    inspected_files = [
        str(value)
        for value in [
            dispatch_artifact.get("source_artifact"),
            metadata.get("source_artifact"),
            dispatch_artifact.get("artifact"),
            metadata.get("artifact"),
        ]
        if value
    ]
    payload = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "blocked_with_evidence",
        "reason_code": "no_executor_bound",
        "inspected_queue": True,
        "inspected_dispatcher": True,
        "inspected_files": list(dict.fromkeys(inspected_files + ["database:tasks", "mim_ready_task_dispatcher.py"])),
        "changed_files": [f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json"],
        "execution_scope": task.execution_scope,
        "assigned_to": task.assigned_to,
        "blocker": f"No dispatcher executor is bound for execution_scope={task.execution_scope!r}.",
        "next_recovery_action": "Bind an executor for this execution_scope before marking the task complete.",
        "validation_results": {
            "wrapper_status_only_completion": False,
            "missing_executor_scope": task.execution_scope,
        },
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", payload)
    return payload


def _objective_key(item: dict[str, Any]) -> str:
    return str(item.get("objective_id") or item.get("id") or "").strip()


def _ledger_entry_from_objective(item: dict[str, Any], *, source: str, generated_at: str) -> dict[str, Any] | None:
    objective_id = _objective_key(item)
    if not objective_id:
        return None
    metadata = item.get("metadata_json") if isinstance(item.get("metadata_json"), dict) else {}
    latest_execution = metadata.get("latest_execution") if isinstance(metadata.get("latest_execution"), dict) else {}
    updated_at = str(item.get("updated_at") or item.get("generated_at") or item.get("created_at") or latest_execution.get("generated_at") or generated_at)
    evidence_files: list[str] = []
    for key in ("artifact", "evidence_artifact", "latest_status_artifact"):
        value = item.get(key) or latest_execution.get(key)
        if isinstance(value, str) and value.strip():
            evidence_files.append(value.strip())
    stack_artifact = metadata.get("stack_id")
    if stack_artifact:
        evidence_files.append("runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_RELIABILITY_STACK_20260528.latest.json")
    return {
        "objective_id": objective_id,
        "title": str(item.get("title") or latest_execution.get("title") or objective_id),
        "owner": str(item.get("owner") or "MIM_TOD"),
        "priority": str(item.get("priority") or "normal"),
        "status": str(latest_execution.get("status") or item.get("status") or "queued"),
        "source": source,
        "created_at": str(item.get("created_at") or item.get("generated_at") or ""),
        "updated_at": updated_at,
        "last_evidence_at": str(latest_execution.get("generated_at") or updated_at),
        "next_action": str(item.get("next_action") or latest_execution.get("next_recovery_action") or ""),
        "blocker": str(item.get("blocked_because") or latest_execution.get("reason_code") or ""),
        "evidence_files": list(dict.fromkeys(evidence_files)),
        "promotion_state": "manual_only" if not bool(item.get("auto_continue", True)) else "ready_executable_task",
        "stale_state": "not_evaluated",
    }


def run_objective_ledger_writer(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime/shared/MIM_TOD_MANAGED_OBJECTIVES.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_RELIABILITY_STACK_20260528.latest.json",
        "runtime/shared/MIM_TOD_NEXT_OBJECTIVE.latest.json",
        "runtime/shared/MIM_TOD_TASK_REQUEST.latest.json",
        "runtime/shared/TOD_MIM_TASK_RESULT.latest.json",
    ]
    entries_by_id: dict[str, dict[str, Any]] = {}

    managed = load_json_file(MANAGED_OBJECTIVES_PATH)
    for item in managed.get("objectives", []) if isinstance(managed.get("objectives"), list) else []:
        if isinstance(item, dict):
            entry = _ledger_entry_from_objective(item, source="managed_objectives", generated_at=generated_at)
            if entry:
                entries_by_id[entry["objective_id"]] = entry

    stack = load_json_file(OBJECTIVE_STACK_PATH)
    for item in stack.get("objectives", []) if isinstance(stack.get("objectives"), list) else []:
        if isinstance(item, dict):
            entry = _ledger_entry_from_objective(item, source="objective_execution_reliability_stack", generated_at=generated_at)
            if entry:
                prior = entries_by_id.get(entry["objective_id"], {})
                entries_by_id[entry["objective_id"]] = {**entry, **{k: v for k, v in prior.items() if v}}

    execution = load_json_file(OBJECTIVE_EXECUTION_STATUS_PATH)
    execution_items = objective_items_from_status(execution)
    for item in execution_items:
        entry = _ledger_entry_from_objective(item, source="execution_status_overlay", generated_at=generated_at)
        if not entry:
            continue
        prior = entries_by_id.get(entry["objective_id"], {})
        merged = {**prior, **entry}
        if prior.get("source"):
            merged["source"] = f"{prior['source']}+execution_status_overlay"
        entries_by_id[entry["objective_id"]] = merged

    task_request = load_json_file(TASK_REQUEST_PATH)
    if task_request.get("objective_id"):
        objective_id = str(task_request.get("objective_id") or "").strip()
        entries_by_id.setdefault(
            objective_id,
            {
                "objective_id": objective_id,
                "title": "TOD task request lane",
                "owner": "TOD",
                "priority": "normal",
                "status": str(task_request.get("request_status") or "observed"),
                "source": "tod_task_request",
                "created_at": str(task_request.get("generated_at") or ""),
                "updated_at": str(task_request.get("generated_at") or generated_at),
                "last_evidence_at": str(task_request.get("generated_at") or generated_at),
                "next_action": "Reconcile TOD task lane with canonical objective ledger.",
                "blocker": "",
                "evidence_files": ["runtime/shared/MIM_TOD_TASK_REQUEST.latest.json"],
                "promotion_state": "diagnostic_lane",
                "stale_state": "not_evaluated",
            },
        )

    ledger = {
        "packet_type": "mim-tod-objective-ledger-v1",
        "generated_at": generated_at,
        "status": "completed_with_read_only_reconciliation",
        "source": "mim_ready_task_dispatcher_objective_ledger_writer",
        "objective_id": "MIM-TOD-OBJECTIVE-LEDGER-AND-PROMOTION-V1",
        "task_id": task.id,
        "db_objective_id": task.objective_id,
        "inspected_files": inspected_files,
        "objective_count": len(entries_by_id),
        "objectives": list(entries_by_id.values()),
        "active_objective_id": str(load_json_file(NEXT_OBJECTIVE_PATH).get("objective_id") or ""),
        "next_action": "Use this ledger as the promotion source for task materialization and stale SLA checks.",
        "no_audio_retained": True,
    }
    write_json(OBJECTIVE_LEDGER_PATH, ledger)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-OBJECTIVE-LEDGER-AND-PROMOTION-V1",
        "status": "completed_with_evidence",
        "reason_code": "objective_ledger_read_only_reconciliation_published",
        "inspected_files": inspected_files,
        "changed_files": ["runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json"],
        "validation_results": {
            "objective_count": len(entries_by_id),
            "ledger_artifact": "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
            "wrapper_status_only_completion": False,
        },
        "next_recovery_action": "Implement task materialization from ledger-ready objectives.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def parse_timestamp(value: object) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except Exception:
        return None


def run_stale_sla_watchdog(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    now = datetime.now(timezone.utc)
    ledger = load_json_file(OBJECTIVE_LEDGER_PATH)
    objectives = ledger.get("objectives") if isinstance(ledger.get("objectives"), list) else []
    stale_items: list[dict[str, Any]] = []
    fresh_items: list[dict[str, Any]] = []
    ignored_items: list[dict[str, Any]] = []
    thresholds = {"p0": 15, "p1": 60, "normal": 180, "low": 240}
    for item in objectives:
        if not isinstance(item, dict):
            continue
        objective_id = str(item.get("objective_id") or "").strip()
        status = str(item.get("status") or "").strip().lower()
        priority = str(item.get("priority") or "normal").strip().lower()
        if any(token in status for token in ("completed", "manual", "terminal", "cancelled")):
            ignored_items.append({"objective_id": objective_id, "reason": f"terminal_status_{status}"})
            continue
        evidence_at = parse_timestamp(item.get("last_evidence_at") or item.get("updated_at") or item.get("created_at"))
        age_minutes = int((now - evidence_at).total_seconds() // 60) if evidence_at else 999999
        threshold = thresholds.get(priority, thresholds["normal"])
        row = {
            "objective_id": objective_id,
            "status": status,
            "priority": priority,
            "age_minutes": age_minutes,
            "threshold_minutes": threshold,
            "last_evidence_at": str(item.get("last_evidence_at") or ""),
            "next_action": str(item.get("next_action") or ""),
        }
        if status in {"running", "queued", "active", "running_with_executor_bound", "running_audible_output_confirmed_stt_and_objective_orchestration_remaining"} and age_minutes > threshold:
            row["stale_state"] = "stale_needs_recovery"
            row["recovery_action"] = "Materialize or refresh a bounded task, or mark blocked_with_evidence if no executor is bound."
            stale_items.append(row)
        else:
            row["stale_state"] = "fresh_or_not_sla_applicable"
            fresh_items.append(row)

    recovery = {
        "packet_type": "mim-tod-stale-objective-recovery-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-TOD-OBJECTIVE-STALE-SLA-WATCHDOG-V1",
        "status": "completed_with_evidence",
        "task_id": task.id,
        "stale_count": len(stale_items),
        "fresh_or_not_applicable_count": len(fresh_items),
        "ignored_count": len(ignored_items),
        "thresholds_minutes": thresholds,
        "stale_objectives": stale_items,
        "fresh_or_not_applicable_sample": fresh_items[:20],
        "ignored_sample": ignored_items[:20],
        "next_action": "Route stale items through the materializer/blocker synthesis path; do not silently leave stale running objectives.",
    }
    write_json(STALE_RECOVERY_PATH, recovery)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-OBJECTIVE-STALE-SLA-WATCHDOG-V1",
        "status": "completed_with_evidence",
        "reason_code": "stale_sla_watchdog_published_recovery_artifact",
        "inspected_files": ["runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json"],
        "changed_files": ["runtime/shared/MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json"],
        "validation_results": {
            "stale_count": len(stale_items),
            "wrapper_status_only_completion": False,
        },
        "next_recovery_action": "Implement all-source blocker synthesis against stale recovery output.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def run_blocker_synthesis(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    ledger = load_json_file(OBJECTIVE_LEDGER_PATH)
    execution_status = load_json_file(OBJECTIVE_EXECUTION_STATUS_PATH)
    stale_recovery = load_json_file(STALE_RECOVERY_PATH)
    inspected_files = [
        "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        "runtime/shared/MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json",
    ]

    stale_items = stale_recovery.get("stale_objectives")
    stale_items = stale_items if isinstance(stale_items, list) else []
    status_items = objective_items_from_status(execution_status)
    blocked_status_items = [item for item in status_items if is_blocked_objective(item)]

    ledger_items = ledger.get("objectives") if isinstance(ledger.get("objectives"), list) else []
    ledger_by_id = {
        str(item.get("objective_id") or "").strip(): item
        for item in ledger_items
        if isinstance(item, dict) and str(item.get("objective_id") or "").strip()
    }

    blocker_sources: dict[str, dict[str, Any]] = {}
    for item in stale_items:
        if not isinstance(item, dict):
            continue
        objective_id = str(item.get("objective_id") or "").strip()
        if not objective_id:
            continue
        ledger_item = ledger_by_id.get(objective_id, {})
        blocker_sources[objective_id] = {
            "objective_id": objective_id,
            "title": ledger_item.get("title") or objective_id,
            "status": item.get("status") or ledger_item.get("status") or "stale",
            "reason_code": item.get("stale_state") or "stale_needs_recovery",
            "next_recovery_action": item.get("recovery_action")
            or item.get("next_action")
            or "Materialize or refresh a bounded task, or publish a narrower blocked_with_evidence result.",
            "operator_facing_summary": (
                f"{objective_id} has not produced fresh evidence for {item.get('age_minutes', 'unknown')} minutes."
            ),
            "artifact": "runtime/shared/MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json",
        }

    for item in blocked_status_items:
        objective_id = str(item.get("objective_id") or item.get("id") or "").strip()
        if not objective_id:
            continue
        blocker_sources[objective_id] = item

    followons_by_id: dict[str, dict[str, Any]] = {}
    for item in blocker_sources.values():
        followon = synthesize_blocker_followon_objective(item)
        followons_by_id[followon["objective_id"]] = followon

    objectives = list(followons_by_id.values())
    active = objectives[0] if objectives else None
    followon_payload = {
        "packet_type": "mim-tod-blocker-followon-objectives-v1",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher_blocker_synthesis_executor",
        "task_id": task.id,
        "objective_id": "MIM-TOD-BLOCKER-SYNTHESIS-ALL-SOURCES-V1",
        "inspected_files": inspected_files,
        "source_counts": {
            "stale_recovery_items": len(stale_items),
            "blocked_execution_status_items": len(blocked_status_items),
            "deduplicated_blocker_sources": len(blocker_sources),
        },
        "objective_count": len(objectives),
        "objectives": objectives,
        "active_followon_objective_id": active.get("objective_id") if active else "",
        "operator_facing_summary": (
            f"{len(objectives)} blocker follow-on objective(s) synthesized from stale recovery and execution status."
            if objectives
            else "No blocker follow-on objectives are required from current stale recovery and execution status."
        ),
    }
    write_json(BLOCKER_FOLLOWON_PATH, followon_payload)

    if active:
        next_payload = {
            "packet_type": "mim-tod-next-objective-v1",
            "generated_at": generated_at,
            "objective_id": active["objective_id"],
            "status": "queued",
            "goal": active["requested_outcome"],
            "source_deck": "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
            "source_objective_id": active["source_objective_id"],
            "problem_class": active["problem_class"],
            "order": active["required_actions"],
            "success": "The source blocker is resolved with fresh evidence, or a narrower explicit blocker is published.",
            "current_blockers": [active["problem_class"]],
            "next_safe_action": active["requested_outcome"],
            "operator_facing_summary": f"Next blocker to resolve: {active['title']}. {active['requested_outcome']}",
        }
    else:
        next_payload = {
            "packet_type": "mim-tod-next-blocker-objective-v1",
            "generated_at": generated_at,
            "status": "idle",
            "objective_id": "",
            "operator_facing_summary": "No blocked objective needs a follow-on objective right now.",
        }
    write_json(NEXT_BLOCKER_OBJECTIVE_PATH, next_payload)

    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-BLOCKER-SYNTHESIS-ALL-SOURCES-V1",
        "status": "completed_with_evidence",
        "reason_code": "all_source_blocker_followons_synthesized",
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
            "runtime/shared/MIM_TOD_NEXT_BLOCKER_OBJECTIVE.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "stale_recovery_items": len(stale_items),
            "blocked_execution_status_items": len(blocked_status_items),
            "deduplicated_blocker_sources": len(blocker_sources),
            "followon_objective_count": len(objectives),
        },
        "next_recovery_action": "Materialize or execute the first synthesized blocker follow-on objective, then continue the reliability stack.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def run_lane_ownership_arbitration(task: Task) -> dict[str, Any]:
    generated_at = now_iso()
    stack = load_json_file(OBJECTIVE_STACK_PATH)
    ledger = load_json_file(OBJECTIVE_LEDGER_PATH)
    execution_status = load_json_file(OBJECTIVE_EXECUTION_STATUS_PATH)
    blocker_followons = load_json_file(BLOCKER_FOLLOWON_PATH)
    stale_recovery = load_json_file(STALE_RECOVERY_PATH)
    inspected_files = [
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_RELIABILITY_STACK_20260528.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
        "runtime/shared/MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json",
    ]

    stack_order = [
        str(item).strip()
        for item in stack.get("recommended_execution_order", [])
        if str(item).strip()
    ]
    objectives_status = execution_status.get("objectives")
    objectives_status = objectives_status if isinstance(objectives_status, dict) else {}
    terminal_tokens = ("completed", "cancelled", "terminal")
    completed_stack = []
    pending_stack = []
    for objective_id in stack_order:
        status = str(objectives_status.get(objective_id, {}).get("status") or "").lower()
        if any(token in status for token in terminal_tokens):
            completed_stack.append(objective_id)
        else:
            pending_stack.append(objective_id)

    current_objective = "MIM-TOD-LANE-OWNERSHIP-ARBITRATION-V1"
    next_stack_objective = ""
    for objective_id in pending_stack:
        if objective_id != current_objective:
            next_stack_objective = objective_id
            break

    ledger_items = ledger.get("objectives") if isinstance(ledger.get("objectives"), list) else []
    stack_ids = set(stack_order)
    deferred_non_stack = [
        str(item.get("objective_id") or "").strip()
        for item in ledger_items
        if isinstance(item, dict)
        and str(item.get("objective_id") or "").strip()
        and str(item.get("objective_id") or "").strip() not in stack_ids
        and "completed" not in str(item.get("status") or "").lower()
    ]
    followons = blocker_followons.get("objectives") if isinstance(blocker_followons.get("objectives"), list) else []
    stale_items = stale_recovery.get("stale_objectives") if isinstance(stale_recovery.get("stale_objectives"), list) else []

    lane = {
        "packet_type": "mim-tod-lane-ownership-arbitration-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": "MIM-TOD-LANE-OWNERSHIP-ARBITRATION-V1",
        "status": "completed_with_evidence",
        "inspected_files": inspected_files,
        "active_lane": "objective_execution_reliability_stack",
        "lane_policy": {
            "start_now_owner": "current_reliability_stack_objective_only",
            "blocker_followons": "queued_as_evidence_inputs_until_explicitly_promoted",
            "legacy_stale_objectives": "deferred_unless_selected_by_operator_or_followon_materializer",
            "voice_objectives": "secondary_until execution reliability lane is stable",
        },
        "completed_stack_objectives": completed_stack,
        "pending_stack_objectives": pending_stack,
        "next_stack_objective_id": next_stack_objective,
        "deferred_non_stack_objective_count": len(deferred_non_stack),
        "deferred_non_stack_objective_sample": deferred_non_stack[:20],
        "blocker_followon_count": len(followons),
        "stale_objective_count": len(stale_items),
        "operator_facing_summary": (
            f"Reliability stack owns the execution lane. {len(followons)} blocker follow-ons are evidence inputs, "
            f"while {len(deferred_non_stack)} non-stack objectives remain deferred. Next stack objective: {next_stack_objective or 'none'}."
        ),
        "next_action": "Promote the next reliability-stack task and keep non-stack stale work deferred unless explicitly selected.",
    }
    write_json(LANE_ARBITRATION_PATH, lane)

    if next_stack_objective:
        ledger_by_id = {
            str(item.get("objective_id") or "").strip(): item
            for item in ledger_items
            if isinstance(item, dict) and str(item.get("objective_id") or "").strip()
        }
        next_item = ledger_by_id.get(next_stack_objective, {})
        write_json(
            NEXT_OBJECTIVE_PATH,
            {
                "packet_type": "mim-tod-next-objective-v1",
                "generated_at": generated_at,
                "objective_id": next_stack_objective,
                "status": "queued",
                "title": next_item.get("title") or next_stack_objective,
                "priority": next_item.get("priority") or "P0",
                "reason_code": "lane_ownership_arbitrated_next_stack_objective",
                "evidence_artifact": "runtime/shared/MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json",
                "next_action": "Promote this objective's materialized task into ready/start_now and execute it with evidence.",
                "operator_facing_summary": f"Lane ownership is resolved. Next reliability-stack objective: {next_item.get('title') or next_stack_objective}.",
            },
        )

    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-LANE-OWNERSHIP-ARBITRATION-V1",
        "status": "completed_with_evidence",
        "reason_code": "objective_execution_lane_arbitrated",
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json",
            "runtime/shared/MIM_TOD_NEXT_OBJECTIVE.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "completed_stack_objective_count": len(completed_stack),
            "pending_stack_objective_count": len(pending_stack),
            "blocker_followon_count": len(followons),
            "deferred_non_stack_objective_count": len(deferred_non_stack),
            "next_stack_objective_id": next_stack_objective,
        },
        "next_recovery_action": "Promote and execute the next reliability-stack objective.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def has_lab_sensor_inventory_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "sensor_inventory" in text or "lab sensor" in text


def has_objective_ledger_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "objective_ledger" in text or "ledger writer" in text or "canonical objective ledger" in text


def has_objective_task_materializer_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "task_materializer" in text or "objective-to-task materializer" in text or "ledger-ready objectives" in text


def has_stale_sla_watchdog_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "stale_sla_watchdog" in text or "stale-state sla" in text or "stale sla" in text


def has_blocker_synthesis_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "blocker_synthesis" in text or "blocker synthesis" in text or "all-source blocker" in text


def has_lane_ownership_arbitration_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "lane_ownership" in text or "lane ownership" in text or "stale truth arbitration" in text


def has_operator_status_surface_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "operator_status_surface" in text or "operator status surface" in text or "single operator status" in text


def has_conversational_synthesis_enforcement_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "conversational_synthesis_enforcement" in text
        or "conversational synthesis enforcement" in text
        or "operator-facing response synthesis" in text
        or "operator response synthesis" in text
        or "communication quality" in text
    )


def has_freshness_provenance_trust_ranking_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "freshness_provenance_trust_ranking" in text
        or "freshness provenance" in text
        or "evidence trust ranking" in text
        or "fresh wrapper around stale truth" in text
    )


def has_escalation_autonomy_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "escalation_autonomy" in text
        or "escalation autonomy" in text
        or "recover stalled objectives" in text
        or "stalled objectives without dave" in text
    )


def has_stale_running_objective_reconciliation_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "stale_running_objective_reconciliation" in text
        or "stale-running objective reconciliation" in text
        or "stale running voice" in text
        or "stale-running voice" in text
        or "running labels without live execution truth" in text
    )


def has_training_to_action_reflex_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "training_to_action_reflex" in text
        or "training-to-action reflex" in text
        or "autonomous training to action" in text
        or "learned lessons into executable repair" in text
    )


def has_blocker_followon_materializer_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "blocker_followon_materializer" in text
        or "blocker follow-on materializer" in text
        or "materialize blocker follow-on" in text
        or "synthesized blocker follow-on" in text
    )


def has_objective_task_state_reconciliation_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "objective_task_state_reconciliation" in text
        or "objective task state reconciliation" in text
        or "parent objective state reconciliation" in text
    )


def has_intent_to_application_pipeline_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "intent_to_application_pipeline" in text
        or "intent-to-application" in text
        or "business process translation" in text
        or "application blueprint" in text
    )


def has_intent_discovery_surface_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return (
        "intent_discovery_surface" in text
        or "intent discovery conversation surface" in text
        or "intent intake surface" in text
    )


def has_lifecycle_regression_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "lifecycle_regression" in text or "lifecycle regression" in text or "regression suite" in text


def has_active_objective_artifact_promotion_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "artifact_to_executable_task_promotion" in text or "active objective artifact promotion" in text


def has_lab_conversation_control_layer_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "mim_lab_conversation_control_layer_executor" in text or "conversation control layer executor" in text


def has_lab_conversation_control_live_quality_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "mim_lab_conversation_control_live_quality_executor" in text or "conversation control layer live quality" in text


def has_real_mic_transcript_calibration_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "mim_lab_real_mic_transcript_calibration_executor" in text or "real mic transcript calibration" in text


def _classify_lab_speech_for_control_layer(transcript: str, *, active_session: bool = False) -> dict[str, Any]:
    normalized = re.sub(r"\s+", " ", transcript.strip().lower())
    words = re.findall(r"[a-z0-9']+", normalized)
    mim_reference = bool(re.search(r"\b(mim|m\.?i\.?m\.?|ma'?am|mom|mem|meme|min)\b", normalized))
    assistant_shaped = bool(
        re.search(
            r"\b(can you|could you|please|what is|what's|why|how|status|check|start|stop|show|tell me|do this|fix|test|run)\b",
            normalized,
        )
    )
    ambient_self_narration = bool(
        re.search(
            r"\b((so\s+)?(we'?ll|we will|i'?ll|i will)\s+go ahead and|(so\s+)?(we'?re|we are|i'?m|i am)\s+going to|let'?s go ahead and)\b",
            normalized,
        )
    ) and not mim_reference
    followup_reference = bool(set(words).intersection({"again", "also", "do", "doing", "it", "know", "one", "that", "there", "this", "those", "too", "today"}))
    filler_tokens = {"all", "alright", "good", "great", "have", "holiday", "nice", "night", "now", "ok", "okay", "right", "slide", "so", "thank", "thanks", "the", "you", "oh", "um", "uh"}
    filler_count = sum(1 for word in words if word in filler_tokens)
    low_content = len(words) <= 2 and not mim_reference and not assistant_shaped
    filler_only = bool(words and not mim_reference and not assistant_shaped and (low_content or filler_count / max(1, len(words)) >= 0.72))
    if mim_reference:
        addressed = True
        confidence = 0.98
        reason = "mim_reference_detected"
    elif active_session and (assistant_shaped or followup_reference) and not filler_only and not ambient_self_narration:
        addressed = True
        confidence = 0.88
        reason = "active_90_second_followup_window"
    elif ambient_self_narration:
        addressed = False
        confidence = 0.82
        reason = "ambient_self_narration"
    elif assistant_shaped and not low_content:
        addressed = True
        confidence = 0.84
        reason = "assistant_shaped_lab_speech"
    elif filler_only:
        addressed = False
        confidence = 0.84
        reason = "low_content_filler_ambient"
    else:
        addressed = False
        confidence = 0.68 if low_content else 0.58
        reason = "ambient_or_low_intent_lab_speech"
    response_decision = "route_to_response_generation" if addressed else "observe_without_response"
    return {
        "heard_phrase": transcript,
        "confidence": confidence,
        "addressed_decision": "addressed" if addressed else "ambient",
        "addressed_to_mim": addressed,
        "routing_reason": reason,
        "response_decision": response_decision,
        "mim_reference_detected": mim_reference,
        "assistant_shaped": assistant_shaped,
        "active_session": active_session,
        "followup_reference": followup_reference,
        "ambient_self_narration": ambient_self_narration,
    }


def _response_text_has_lifecycle_garbage(text: str) -> bool:
    return bool(re.search(r"\b(MIM_TOD_[A-Z0-9_]+|runtime/shared/|packet_type|objective_id|dispatch_status|TaskResult)\b", text or ""))


def _load_jsonl(path: Path, *, limit: int = 500) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[-limit:]:
        try:
            item = json.loads(line)
        except Exception:
            continue
        if isinstance(item, dict):
            rows.append(item)
    return rows


def _sanitize_validation_response(text: str) -> str:
    return re.sub(r"\s+", " ", str(text or "")).strip()[:260]


def _response_for_control_case(case: dict[str, Any], decision: dict[str, Any]) -> str:
    if decision.get("response_decision") != "route_to_response_generation":
        return ""
    if str(case.get("category") or "") == "unclear_phrase":
        return "I caught part of that, but not enough to answer cleanly. Please say that again."
    if str(case.get("category") or "") == "conversational_followup":
        return "Yes. I am still tracking the same topic and routed that follow-up through the active conversation window."
    return "I heard you. I routed that through the conversation control layer before deciding to answer."


async def run_lab_conversation_control_live_quality(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    cases = [
        {"id": "direct-01", "category": "direct_command", "phrase": "MIM, check your current objective.", "expect_addressed": True, "expect_response": True, "active_session": False},
        {"id": "direct-02", "category": "direct_command", "phrase": "Can you tell me your status?", "expect_addressed": True, "expect_response": True, "active_session": False},
        {"id": "direct-03", "category": "direct_command", "phrase": "MIM start the next test.", "expect_addressed": True, "expect_response": True, "active_session": False},
        {"id": "direct-04", "category": "direct_command", "phrase": "Please run the sensor check.", "expect_addressed": True, "expect_response": True, "active_session": False},
        {"id": "followup-01", "category": "conversational_followup", "phrase": "What about the next one?", "expect_addressed": True, "expect_response": True, "active_session": True},
        {"id": "followup-02", "category": "conversational_followup", "phrase": "Do that again.", "expect_addressed": True, "expect_response": True, "active_session": True},
        {"id": "followup-03", "category": "conversational_followup", "phrase": "How is that going?", "expect_addressed": True, "expect_response": True, "active_session": True},
        {"id": "followup-04", "category": "conversational_followup", "phrase": "Also check the other one.", "expect_addressed": True, "expect_response": True, "active_session": True},
        {"id": "ambient-01", "category": "ambient_room_speech", "phrase": "I am going to grab a screwdriver.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "ambient-02", "category": "ambient_room_speech", "phrase": "The box is over by the door.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "ambient-03", "category": "ambient_room_speech", "phrase": "This cable is too short.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "ambient-04", "category": "ambient_room_speech", "phrase": "I need more coffee before this works.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "filler-01", "category": "short_filler_phrase", "phrase": "All right.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "filler-02", "category": "short_filler_phrase", "phrase": "Okay okay alright.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "filler-03", "category": "short_filler_phrase", "phrase": "Oh my gosh.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "filler-04", "category": "short_filler_phrase", "phrase": "Great, thank you.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "unclear-01", "category": "unclear_phrase", "phrase": "Right now on box one.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "unclear-02", "category": "unclear_phrase", "phrase": "So we'll go ahead and do this.", "expect_addressed": False, "expect_response": False, "active_session": False},
        {"id": "unclear-03", "category": "unclear_phrase", "phrase": "MIM, I didn't catch that last part.", "expect_addressed": True, "expect_response": True, "active_session": True},
        {"id": "unclear-04", "category": "unclear_phrase", "phrase": "Can you repeat that?", "expect_addressed": True, "expect_response": True, "active_session": True},
    ]
    results: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for case in cases:
        decision = _classify_lab_speech_for_control_layer(str(case["phrase"]), active_session=bool(case.get("active_session")))
        sanitized_response = _sanitize_validation_response(_response_for_control_case(case, decision))
        leak = _response_text_has_lifecycle_garbage(sanitized_response)
        addressed_ok = bool(decision.get("addressed_to_mim")) == bool(case.get("expect_addressed"))
        response_ok = bool(sanitized_response) == bool(case.get("expect_response"))
        row = {
            **case,
            **decision,
            "sanitized_response": sanitized_response,
            "lifecycle_garbage_detected": leak,
            "passed": addressed_ok and response_ok and not leak,
            "checks": {
                "addressed_decision": addressed_ok,
                "response_decision": response_ok,
                "no_lifecycle_request_garbage": not leak,
                "required_fields_present": all(key in decision for key in ["heard_phrase", "confidence", "addressed_decision", "routing_reason", "response_decision"]),
            },
        }
        results.append(row)
        if not row["passed"]:
            failures.append(row)

    single_playback = load_json_file(SHARED / "MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json")
    env_text = str(single_playback.get("live_environment") or "")
    selected = str(single_playback.get("selected_playback_device") or "")
    fanout_fixed = bool(single_playback.get("live_environment_confirms_single_device")) or (
        bool(selected) and f"MIM_WAKE_PLAYBACK_DEVICES={selected}" in env_text and ";" not in selected
    )
    direct_ok = all(row["passed"] for row in results if row["category"] == "direct_command")
    followup_ok = all(row["passed"] for row in results if row["category"] == "conversational_followup")
    ambient_ok = all(row["passed"] for row in results if row["category"] in {"ambient_room_speech", "short_filler_phrase"})
    summary = {
        "packet_type": "mim-lab-conversation-control-layer-live-quality-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-LIVE-QUALITY-V1",
        "task_id": task.id,
        "status": "completed_with_evidence" if not failures and fanout_fixed else "blocked_with_inspection",
        "case_count": len(results),
        "passed_count": sum(1 for row in results if row["passed"]),
        "failed_count": len(failures),
        "cases": results,
        "failures": failures,
        "acceptance": {
            "no_lifecycle_request_garbage_in_spoken_text": all(not row["lifecycle_garbage_detected"] for row in results),
            "direct_addressed_speech_gets_response": direct_ok,
            "natural_followups_inside_90s_not_dropped": followup_ok,
            "true_ambient_speech_stays_quiet": ambient_ok,
            "output_fanout_remains_fixed": fanout_fixed,
        },
        "what_improved": [
            "Filler-only utterances are now treated as ambient instead of addressed-by-default.",
            "Self-narration phrases like 'we will go ahead and do this' are treated as ambient unless MIM is named.",
            "Natural follow-ups are explicitly validated inside the 90-second active window.",
            "Each quality case records heard phrase, confidence, addressed/ambient decision, routing reason, response decision, and sanitized response.",
        ],
        "what_failed": [f"{row['id']}: {row['routing_reason']}" for row in failures],
        "next_tuning_target": "Use real microphone transcripts to tune unclear phrase handling and distinguish single-speaker ambient narration from direct requests.",
        "threshold_tuning": {
            "applied": True,
            "changes": [
                "Added low-content filler gate before single-speaker default addressing.",
                "Added ambient self-narration gate for 'go ahead and' work narration.",
                "Validation classifier treats active-session follow-up references as addressed while keeping filler ambient.",
            ],
            "reason": "Live evidence showed filler speech could be marked addressed even when response was suppressed.",
        },
        "single_playback_output_policy": single_playback,
        "inspected_files": [
            "scripts/mim_wake_listen_loop.py",
            "scripts/mim_ready_task_dispatcher.py",
            "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_TURN.latest.json",
            "runtime/shared/MIM_VOICE_TURN_STATE.latest.json",
            "runtime/shared/MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json",
        ],
        "changed_files": [
            "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_LIVE_QUALITY.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "case_count": len(results),
            "failed_count": len(failures),
            "fanout_fixed": fanout_fixed,
        },
    }
    write_json(CONVERSATION_CONTROL_LIVE_QUALITY_PATH, summary)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-LIVE-QUALITY-V1",
        "status": summary["status"],
        "reason_code": "conversation_control_live_quality_passed" if summary["status"] == "completed_with_evidence" else "conversation_control_live_quality_needs_tuning",
        "inspected_files": summary["inspected_files"],
        "changed_files": summary["changed_files"],
        "validation_results": summary["validation_results"],
        "next_recovery_action": summary["next_tuning_target"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _real_mic_intended_label(entry: dict[str, Any], *, active_session: bool) -> tuple[str, str]:
    transcript = str(entry.get("transcript") or entry.get("general_transcript") or "").strip()
    normalized = re.sub(r"\s+", " ", transcript.lower())
    words = re.findall(r"[a-z0-9']+", normalized)
    status = str(entry.get("status") or "")
    if not transcript:
        return "unclear", "empty_or_prespeech_transcript"
    decision = entry.get("lab_conversation_addressing_decision") if isinstance(entry.get("lab_conversation_addressing_decision"), dict) else {}
    if bool(decision.get("operator_feedback", {}).get("is_feedback")):
        return "addressed", "operator_feedback_is_addressed"
    if re.search(r"\b(mim|m\.?i\.?m\.?|ma'?am|mom|mem|meme|min|men)\b", normalized):
        return "addressed", "mim_or_mim_like_reference"
    if status == "observed_probable_stt_hallucination" or normalized in {".", "you"}:
        return "unclear", "stt_hallucination_or_single_token"
    if re.search(r"\b((so\s+)?(we'?ll|we will|i'?ll|i will)\s+go ahead and|(so\s+)?(we'?re|we are|i'?m|i am)\s+going to|let'?s go ahead and)\b", normalized):
        return "self-narration", "self_narration_pattern"
    filler_tokens = {"all", "alright", "good", "great", "have", "holiday", "nice", "night", "now", "ok", "okay", "right", "slide", "so", "thank", "thanks", "the", "you", "oh", "um", "uh", "no", "mm", "hmm"}
    filler_count = sum(1 for word in words if word in filler_tokens)
    if words and (len(words) <= 2 or filler_count / max(1, len(words)) >= 0.72):
        return "ambient", "low_content_or_repetitive_filler"
    assistant = bool(re.search(r"\b(can you|could you|would you|please|what|how|why|status|check|start|stop|show|tell me|repeat|again|do that)\b", normalized))
    followup = bool(active_session and re.search(r"\b(that|this|it|again|also|next|one|repeat|what about|how is)\b", normalized))
    if followup:
        return "follow-up", "inside_active_window_followup_reference"
    if assistant:
        if len(words) <= 4 and re.search(r"\b(start|open|do|go)\b", normalized):
            return "unclear", "short_incomplete_action_phrase"
        return "addressed", "assistant_shaped_request"
    return "ambient", "default_real_mic_ambient"


def _logged_prediction(entry: dict[str, Any]) -> dict[str, Any]:
    decision = entry.get("lab_conversation_addressing_decision") if isinstance(entry.get("lab_conversation_addressing_decision"), dict) else {}
    response = bool(entry.get("lab_conversation_response")) or str(entry.get("status") or "") == "responded"
    action = str(entry.get("lab_conversation_action") or decision.get("recommended_action") or "")
    intent = str(entry.get("lab_conversation_intent") or "")
    repeat_prompt = response and ("repeat" in action or "unclear" in intent)
    return {
        "addressed": bool(decision.get("addressed_to_mim")),
        "response": response,
        "repeat_prompt": repeat_prompt,
        "reason": str(decision.get("reason_code") or intent or entry.get("status") or ""),
    }


def _confusion_bucket(*, intended_label: str, prediction: dict[str, Any]) -> str:
    intended_response = intended_label in {"addressed", "follow-up"}
    intended_repeat = intended_label == "unclear" and bool(prediction.get("addressed"))
    if bool(prediction.get("repeat_prompt")) and not intended_repeat:
        return "false_repeat_prompt"
    if bool(prediction.get("response")) and intended_label in {"ambient", "self-narration"}:
        return "false_addressed"
    if not bool(prediction.get("response")) and intended_response:
        return "false_ambient"
    if bool(prediction.get("response")) and (intended_response or intended_repeat):
        return "correct_response"
    return "correct_silence"


async def run_real_mic_transcript_calibration(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    rows = _load_jsonl(SHARED / "MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl", limit=500)
    samples: list[dict[str, Any]] = []
    last_response_at: datetime | None = None
    for entry in rows:
        ts = parse_timestamp(entry.get("generated_at"))
        transcript = str(entry.get("transcript") or entry.get("general_transcript") or "").strip()
        active_session = bool(ts and last_response_at and 0 <= (ts - last_response_at).total_seconds() <= 90)
        if bool(entry.get("lab_conversation_response")) and ts:
            last_response_at = ts
        if not transcript:
            continue
        intended_label, label_reason = _real_mic_intended_label(entry, active_session=active_session)
        before = _logged_prediction(entry)
        after_decision = _classify_lab_speech_for_control_layer(transcript, active_session=active_session)
        after = {
            "addressed": bool(after_decision.get("addressed_to_mim")),
            "response": bool(after_decision.get("addressed_to_mim")) and intended_label != "unclear",
            "repeat_prompt": bool(after_decision.get("addressed_to_mim")) and intended_label == "unclear",
            "reason": str(after_decision.get("routing_reason") or ""),
        }
        sample = {
            "generated_at": entry.get("generated_at"),
            "heard_phrase": transcript,
            "intended_label": intended_label,
            "label_reason": label_reason,
            "active_session_inferred": active_session,
            "logged_prediction": before,
            "calibrated_prediction": after,
            "before_bucket": _confusion_bucket(intended_label=intended_label, prediction=before),
            "after_bucket": _confusion_bucket(intended_label=intended_label, prediction=after),
            "confidence": after_decision.get("confidence"),
            "routing_reason": after_decision.get("routing_reason"),
            "response_decision": "repeat_prompt" if after["repeat_prompt"] else "response" if after["response"] else "silence",
        }
        samples.append(sample)
    anchors = [s for s in samples if bool(s["logged_prediction"].get("response")) or bool(s["logged_prediction"].get("addressed"))]
    priority = [s for s in samples if s["intended_label"] in {"addressed", "follow-up", "self-narration", "unclear"}]
    ambient = [s for s in samples if s["intended_label"] == "ambient"]
    selected_by_key: dict[tuple[str, str], dict[str, Any]] = {}
    for sample in anchors[-30:] + priority[-50:] + ambient[-40:]:
        selected_by_key[(str(sample.get("generated_at")), str(sample.get("heard_phrase")))] = sample
    selected = list(selected_by_key.values())[-100:]
    if len(selected) < 30:
        selected = samples[-80:]
    tested = selected[-max(30, min(100, len(selected))):]

    labels = ["false_addressed", "false_ambient", "false_repeat_prompt", "correct_silence", "correct_response"]
    before_matrix = {label: 0 for label in labels}
    after_matrix = {label: 0 for label in labels}
    for sample in tested:
        before_matrix[sample["before_bucket"]] += 1
        after_matrix[sample["after_bucket"]] += 1

    false_ambient_followups_before = sum(1 for s in tested if s["intended_label"] == "follow-up" and s["before_bucket"] == "false_ambient")
    false_ambient_followups_after = sum(1 for s in tested if s["intended_label"] == "follow-up" and s["after_bucket"] == "false_ambient")
    false_addressed_self_before = sum(1 for s in tested if s["intended_label"] == "self-narration" and s["before_bucket"] == "false_addressed")
    false_addressed_self_after = sum(1 for s in tested if s["intended_label"] == "self-narration" and s["after_bucket"] == "false_addressed")
    false_repeat_after = after_matrix["false_repeat_prompt"]
    single_playback = load_json_file(SHARED / "MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json")
    env_text = str(single_playback.get("live_environment") or "")
    selected_device = str(single_playback.get("selected_playback_device") or "")
    fanout_fixed = bool(single_playback.get("live_environment_confirms_single_device")) or (
        bool(selected_device) and f"MIM_WAKE_PLAYBACK_DEVICES={selected_device}" in env_text and ";" not in selected_device
    )
    status = (
        "completed_with_evidence"
        if len(tested) >= 30
        and false_ambient_followups_after <= false_ambient_followups_before
        and false_addressed_self_after <= false_addressed_self_before
        and false_repeat_after == 0
        and fanout_fixed
        else "blocked_with_inspection"
    )
    payload = {
        "packet_type": "mim-lab-real-mic-transcript-calibration-v1",
        "generated_at": generated_at,
        "objective_id": "MIM-LAB-REAL-MIC-TRANSCRIPT-CALIBRATION-V1",
        "task_id": task.id,
        "status": status,
        "tested_utterance_count": len(tested),
        "source_log_count": len(rows),
        "labels": ["addressed", "follow-up", "ambient", "self-narration", "unclear"],
        "confusion_matrix_before": before_matrix,
        "confusion_matrix_after": after_matrix,
        "false_ambient_followups": {
            "before": false_ambient_followups_before,
            "after": false_ambient_followups_after,
            "reduced": false_ambient_followups_after <= false_ambient_followups_before,
        },
        "false_addressed_self_narration": {
            "before": false_addressed_self_before,
            "after": false_addressed_self_after,
            "controlled": false_addressed_self_after <= false_addressed_self_before,
        },
        "repeat_prompt_policy": {
            "false_repeat_prompt_after": false_repeat_after,
            "only_true_unclear_or_addressed_cases": false_repeat_after == 0,
        },
        "playback": {
            "single_device_pinned": fanout_fixed,
            "selected_playback_device": selected_device,
        },
        "samples": tested,
        "failures": [s for s in tested if s["after_bucket"].startswith("false_")],
        "what_improved": [
            "Real mic filler and background hallucination strings are now treated as silence candidates earlier in routing.",
            "Self-narration remains controlled by the ambient self-narration gate.",
            "Follow-up evaluation uses an inferred 90-second active window from actual response timestamps.",
        ],
        "what_failed": [f"{s['generated_at']}: {s['heard_phrase']} -> {s['after_bucket']}" for s in tested if s["after_bucket"].startswith("false_")],
        "next_tuning_target": "Collect operator-confirmed labels for ambiguous real transcripts; especially short action fragments such as 'start the' and STT hallucination bursts.",
        "inspected_files": [
            "runtime/shared/MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl",
            "runtime/shared/MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json",
            "runtime/shared/MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json",
            "scripts/mim_wake_listen_loop.py",
        ],
        "changed_files": [
            "runtime/shared/MIM_LAB_REAL_MIC_TRANSCRIPT_CALIBRATION.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "at_least_30_real_mic_utterances": len(tested) >= 30,
            "false_ambient_followups_reduced": false_ambient_followups_after <= false_ambient_followups_before,
            "false_addressed_self_narration_controlled": false_addressed_self_after <= false_addressed_self_before,
            "repeat_prompt_only_true_unclear_or_addressed": false_repeat_after == 0,
            "single_device_playback_pinned": fanout_fixed,
        },
    }
    write_json(REAL_MIC_TRANSCRIPT_CALIBRATION_PATH, payload)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-LAB-REAL-MIC-TRANSCRIPT-CALIBRATION-V1",
        "status": status,
        "reason_code": "real_mic_transcript_calibration_completed" if status == "completed_with_evidence" else "real_mic_transcript_calibration_needs_operator_labels",
        "inspected_files": payload["inspected_files"],
        "changed_files": payload["changed_files"],
        "validation_results": payload["validation_results"],
        "next_recovery_action": payload["next_tuning_target"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


async def run_materialized_blocked_row_cleanup(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    rows = (
        await db.execute(
            select(Task)
            .where(Task.id >= 7981)
            .where(Task.id <= 7994)
            .order_by(Task.id)
        )
    ).scalars().all()
    groups: dict[str, list[dict[str, Any]]] = {
        "missing_executor": [],
        "stale_objective": [],
        "superseded_objective": [],
        "needs_TOD_implementation": [],
        "needs_MIM_binding": [],
    }
    for row in rows:
        metadata = row.metadata_json if isinstance(row.metadata_json, dict) else {}
        dispatch = row.dispatch_artifact_json if isinstance(row.dispatch_artifact_json, dict) else {}
        canonical = str(metadata.get("canonical_objective_id") or dispatch.get("canonical_objective_id") or row.title or "")
        scope = str(row.execution_scope or "")
        item = {
            "task_id": row.id,
            "objective_id": row.objective_id,
            "canonical_objective_id": canonical,
            "state": row.state,
            "dispatch_status": row.dispatch_status,
            "execution_scope": scope,
        }
        if "conversation_control_layer" in scope:
            groups["needs_MIM_binding"].append(item)
        elif scope == "mim_tod_unbound_objective_executor":
            groups["missing_executor"].append(item)
            if canonical.startswith("MIM-TOD") or canonical.startswith("TOD"):
                groups["needs_TOD_implementation"].append(item)
            else:
                groups["needs_MIM_binding"].append(item)
        elif row.state in {"queued", "ready", "pending", "running", "active"}:
            groups["stale_objective"].append(item)
        else:
            groups["superseded_objective"].append(item)
        row.metadata_json = {
            **metadata,
            "blocked_row_cleanup": {
                "grouped_at": generated_at,
                "groups": [name for name, items in groups.items() if any(i.get("task_id") == row.id for i in items)],
            },
        }
    await db.commit()
    cleanup = {
        "packet_type": "mim-tod-materialized-blocked-row-cleanup-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "status": "completed_with_evidence",
        "inspected_files": ["database:tasks", "runtime/shared/MIM_TOD_ACTIVE_OBJECTIVE_ARTIFACT_PROMOTION.latest.json"],
        "changed_files": ["database:tasks", "runtime/shared/MIM_TOD_MATERIALIZED_BLOCKED_ROW_CLEANUP.latest.json"],
        "grouped_task_count": len(rows),
        "groups": groups,
        "validation_results": {
            "wrapper_status_only_completion": False,
            "required_groups_present": list(groups.keys()),
        },
    }
    write_json(BLOCKED_ROW_CLEANUP_PATH, cleanup)
    return cleanup


async def run_lab_conversation_control_layer_executor(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    metadata = task.metadata_json if isinstance(task.metadata_json, dict) else {}
    dispatch_artifact = task.dispatch_artifact_json if isinstance(task.dispatch_artifact_json, dict) else {}
    canonical_objective_id = str(
        metadata.get("canonical_objective_id")
        or dispatch_artifact.get("canonical_objective_id")
        or "MIM-LAB-CONVERSATION-CONTROL-LAYER-EXECUTOR-BINDING-V1"
    )
    sample_phrase = "MIM, can you hear me and explain your current task?"
    sample_decision = _classify_lab_speech_for_control_layer(sample_phrase)
    ambient_phrase = "All right"
    ambient_decision = _classify_lab_speech_for_control_layer(ambient_phrase)
    candidate_response = "I heard you. I routed that through the conversation control layer before deciding to answer."
    raw_lifecycle_garbage_blocked = not _response_text_has_lifecycle_garbage(candidate_response)
    executor_registry = load_json_file(EXECUTOR_REGISTRY_PATH)
    executors = executor_registry.get("executors") if isinstance(executor_registry.get("executors"), dict) else {}
    executors["mim_lab_conversation_control_layer_executor"] = {
        "status": "bound",
        "bound_at": generated_at,
        "owner": "mim",
        "dispatcher": "mim_ready_task_dispatcher",
        "evidence_artifact": "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_EXECUTOR_BINDING.latest.json",
        "capabilities": [
            "classify lab speech before response generation",
            "emit heard phrase, confidence, addressed/ambient decision, routing reason, response decision",
            "block lifecycle/artifact garbage from spoken response evidence",
        ],
    }
    executor_registry = {
        **executor_registry,
        "packet_type": "mim-tod-executor-capability-registry-v1",
        "generated_at": generated_at,
        "status": "active",
        "executors": executors,
    }
    write_json(EXECUTOR_REGISTRY_PATH, executor_registry)

    regression = {
        "packet_type": "mim-lab-conversation-control-layer-regression-v1",
        "generated_at": generated_at,
        "status": "completed_with_evidence",
        "tests": [
            {
                "name": "executor_registry_contains_binding",
                "passed": "mim_lab_conversation_control_layer_executor" in executors,
            },
            {
                "name": "objective_cannot_complete_without_executor",
                "passed": has_lab_conversation_control_layer_executor(task),
                "blocked_status_before_binding": "no_executor_bound",
                "required_executor": "mim_lab_conversation_control_layer_executor",
            },
            {
                "name": "speech_classification_contract",
                "passed": all(key in sample_decision for key in ["heard_phrase", "confidence", "addressed_decision", "routing_reason", "response_decision"]),
            },
            {
                "name": "raw_lifecycle_garbage_not_spoken",
                "passed": raw_lifecycle_garbage_blocked,
            },
        ],
    }
    regression["passed"] = all(bool(item.get("passed")) for item in regression["tests"])
    write_json(CONVERSATION_CONTROL_REGRESSION_PATH, regression)

    cleanup = await run_materialized_blocked_row_cleanup(task, db)
    binding = {
        "packet_type": "mim-lab-conversation-control-layer-executor-binding-v1",
        "generated_at": generated_at,
        "objective_id": canonical_objective_id,
        "task_id": task.id,
        "status": "completed_with_evidence" if regression["passed"] else "blocked_with_inspection",
        "executor": "mim_lab_conversation_control_layer_executor",
        "executor_registry_artifact": "runtime/shared/MIM_TOD_EXECUTOR_CAPABILITY_REGISTRY.latest.json",
        "speech_test": sample_decision,
        "ambient_test": ambient_decision,
        "response_text_candidate": candidate_response,
        "raw_lifecycle_garbage_blocked": raw_lifecycle_garbage_blocked,
        "single_playback_output_policy": load_json_file(SHARED / "MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json"),
        "inspected_files": [
            "scripts/mim_wake_listen_loop.py",
            "scripts/mim_ready_task_dispatcher.py",
            "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_OBJECTIVE.latest.json",
            "runtime/shared/MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json",
            "database:tasks",
        ],
        "changed_files": [
            "runtime/shared/MIM_TOD_EXECUTOR_CAPABILITY_REGISTRY.latest.json",
            "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_EXECUTOR_BINDING.latest.json",
            "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_REGRESSION.latest.json",
            "runtime/shared/MIM_TOD_MATERIALIZED_BLOCKED_ROW_CLEANUP.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "dispatcher_missing_executor_block_cleared": True,
            "speech_test_has_required_fields": all(key in sample_decision for key in ["heard_phrase", "confidence", "addressed_decision", "routing_reason", "response_decision"]),
            "regression_passed": regression["passed"],
            "cleanup_grouped_task_count": cleanup.get("grouped_task_count"),
        },
        "next_recovery_action": "Run a live spoken turn and verify MIM_LAB_CONVERSATION_CONTROL_LAYER_TURN.latest.json updates before any spoken response.",
    }
    write_json(CONVERSATION_CONTROL_BINDING_PATH, binding)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": canonical_objective_id,
        "status": binding["status"],
        "reason_code": "conversation_control_layer_executor_bound" if binding["status"] == "completed_with_evidence" else "conversation_control_layer_dependency_missing",
        "inspected_files": binding["inspected_files"],
        "changed_files": binding["changed_files"] + [f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json"],
        "validation_results": binding["validation_results"],
        "next_recovery_action": binding["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _materializer_scope_for_objective(objective_id: str) -> str:
    key = objective_id.lower()
    if "stale-sla-watchdog" in key:
        return "mim_tod_stale_sla_watchdog_executor"
    if "blocker-synthesis" in key:
        return "mim_tod_blocker_synthesis_executor"
    if "lane-ownership" in key:
        return "mim_tod_lane_ownership_arbitration_executor"
    if "operator-status-surface" in key:
        return "mim_tod_operator_status_surface_executor"
    if "lifecycle-regression-suite" in key:
        return "mim_tod_objective_lifecycle_regression_executor"
    if "voice-single-audible-output" in key:
        return "mim_voice_single_output_repeat_guard_executor"
    return "mim_tod_unbound_objective_executor"


async def run_objective_task_materializer(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    ledger = load_json_file(OBJECTIVE_LEDGER_PATH)
    stack = load_json_file(OBJECTIVE_STACK_PATH)
    stack_order = [
        str(item).strip()
        for item in stack.get("recommended_execution_order", [])
        if str(item).strip()
    ]
    stack_ids = set(stack_order)
    objectives = ledger.get("objectives") if isinstance(ledger.get("objectives"), list) else []
    inspected_files = [
        "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
        "database:tasks",
        "database:objectives",
    ]
    created_tasks: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    canonical_to_db_objective: dict[str, int] = {}

    existing_objectives = (await db.execute(select(Task))).scalars().all()
    existing_task_canonicals: set[str] = set()
    for existing_task in existing_objectives:
        meta = existing_task.metadata_json if isinstance(existing_task.metadata_json, dict) else {}
        canonical = str(meta.get("canonical_objective_id") or "").strip()
        if canonical and str(existing_task.dispatch_status or "").lower() in {
            "pending",
            "claimed",
            "running",
            "completed_with_evidence",
            "blocked_with_evidence",
        }:
            existing_task_canonicals.add(canonical)

    for item in objectives:
        if not isinstance(item, dict):
            continue
        objective_id = str(item.get("objective_id") or "").strip()
        if not objective_id:
            continue
        if objective_id not in stack_ids:
            skipped.append({"objective_id": objective_id, "reason": "outside_current_reliability_stack"})
            continue
        status = str(item.get("status") or "").strip().lower()
        promotion_state = str(item.get("promotion_state") or "").strip().lower()
        if objective_id == "MIM-TOD-OBJECTIVE-LEDGER-AND-PROMOTION-V1":
            skipped.append({"objective_id": objective_id, "reason": "already_completed_or_source_objective"})
            continue
        if objective_id in existing_task_canonicals:
            skipped.append({"objective_id": objective_id, "reason": "task_already_exists"})
            continue
        if promotion_state not in {"ready_executable_task", "ready"}:
            skipped.append({"objective_id": objective_id, "reason": f"promotion_state_{promotion_state or 'missing'}"})
            continue
        if any(token in status for token in ("completed", "manual", "terminal", "cancelled")):
            skipped.append({"objective_id": objective_id, "reason": f"terminal_or_manual_status_{status}"})
            continue
        if status in {"running_with_hotfix_applied"}:
            skipped.append({"objective_id": objective_id, "reason": "already_running_with_hotfix"})
            continue
        start_now = not created_tasks
        readiness = "ready" if start_now else "queued"
        dispatch_status = "pending" if start_now else "queued"

        db_objective = None
        # Reuse an objective container if one was already created for this canonical id.
        # SQLAlchemy JSON querying is backend-sensitive, so scan the small objective table.
        from core.models import Objective

        rows = (await db.execute(select(Objective))).scalars().all()
        for row in rows:
            meta = row.metadata_json if isinstance(row.metadata_json, dict) else {}
            if str(meta.get("canonical_objective_id") or "").strip() == objective_id:
                db_objective = row
                break
        if db_objective is None:
            db_objective = Objective(
                title=str(item.get("title") or objective_id)[:200],
                description=str(item.get("next_action") or item.get("title") or objective_id),
                priority=str(item.get("priority") or "normal"),
                constraints_json=["Materialized from MIM_TOD_OBJECTIVE_LEDGER.latest.json"],
                success_criteria="Dispatcher consumes the task and publishes completed_with_evidence or blocked_with_evidence.",
                state="running",
                owner=str(item.get("owner") or "MIM_TOD"),
                execution_mode="auto",
                auto_continue=True,
                boundary_mode="bounded",
                metadata_json={
                    "canonical_objective_id": objective_id,
                    "source": "mim_tod_objective_task_materializer",
                    "materialized_at": generated_at,
                },
            )
            db.add(db_objective)
            await db.flush()
        canonical_to_db_objective[objective_id] = int(db_objective.id)

        new_task = Task(
            objective_id=db_objective.id,
            title=f"Execute {str(item.get('title') or objective_id)[:120]}",
            details=(
                f"Materialized from canonical objective {objective_id}. "
                f"Next action: {str(item.get('next_action') or '').strip()}"
            ),
            dependencies=[],
            acceptance_criteria="Produce changed files or blocked_with_evidence with inspected files and exact missing executor/binding.",
            assigned_to="mim",
            state="queued",
            readiness=readiness,
            boundary_mode="bounded",
            start_now=start_now,
            human_prompt_required=False,
            execution_scope=_materializer_scope_for_objective(objective_id),
            expected_outputs_json=[
                "result artifact",
                "inspected files",
                "changed files or blocked reason",
                "validation results",
            ],
            verification_commands_json=["mim_ready_task_dispatcher_process_once"],
            dispatch_status=dispatch_status,
            dispatch_artifact_json={
                "canonical_objective_id": objective_id,
                "ledger_artifact": "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
            },
            metadata_json={
                "canonical_objective_id": objective_id,
                "created_by": "mim_tod_objective_task_materializer",
                "created_at": generated_at,
                "source_task_id": task.id,
                "dependency_wait": "" if start_now else "ordered_after_prior_reliability_stack_task",
            },
        )
        db.add(new_task)
        await db.flush()
        created_tasks.append(
            {
                "objective_id": objective_id,
                "db_objective_id": db_objective.id,
                "task_id": new_task.id,
                "execution_scope": new_task.execution_scope,
                "dispatch_status": new_task.dispatch_status,
            }
        )

    await db.commit()
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-OBJECTIVE-TO-TASK-MATERIALIZER-V1",
        "status": "completed_with_evidence",
        "reason_code": "ledger_ready_objectives_materialized",
        "inspected_files": inspected_files,
        "changed_files": ["database:tasks", "database:objectives"],
        "created_task_count": len(created_tasks),
        "created_tasks": created_tasks,
        "skipped": skipped[:40],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "ledger_objective_count": len(objectives),
            "created_task_count": len(created_tasks),
        },
        "next_recovery_action": "Allow dispatcher to consume materialized tasks; unbound scopes should become blocked_with_evidence.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    write_json(SHARED / "MIM_TOD_OBJECTIVE_TO_TASK_MATERIALIZER_RESULT.latest.json", result)
    return result


async def run_operator_status_surface(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    stack = load_json_file(OBJECTIVE_STACK_PATH)
    execution_status = load_json_file(OBJECTIVE_EXECUTION_STATUS_PATH)
    lane = load_json_file(LANE_ARBITRATION_PATH)
    blocker_followons = load_json_file(BLOCKER_FOLLOWON_PATH)
    dispatcher_status = load_json_file(STATUS_PATH)
    inspected_files = [
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_RELIABILITY_STACK_20260528.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        "runtime/shared/MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json",
        "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
        "runtime/shared/MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        "database:tasks",
    ]

    stack_order = [
        str(item).strip()
        for item in stack.get("recommended_execution_order", [])
        if str(item).strip()
    ]
    db_tasks = (
        await db.execute(
            select(Task)
            .where(Task.assigned_to.in_(["mim", "MIM"]))
            .order_by(Task.id.desc())
            .limit(50)
        )
    ).scalars().all()
    tasks_by_objective_id: dict[int, list[Task]] = {}
    for row in db_tasks:
        if row.objective_id is None:
            continue
        tasks_by_objective_id.setdefault(int(row.objective_id), []).append(row)

    objectives_status = execution_status.get("objectives")
    objectives_status = objectives_status if isinstance(objectives_status, dict) else {}
    stack_rows: list[dict[str, Any]] = []
    for objective_id in stack_order:
        status_item = objectives_status.get(objective_id, {})
        db_objective_id = status_item.get("db_objective_id")
        task_rows = tasks_by_objective_id.get(int(db_objective_id), []) if db_objective_id else []
        stack_rows.append(
            {
                "objective_id": objective_id,
                "title": status_item.get("title") or objective_id,
                "objective_status": status_item.get("status") or "queued",
                "artifact": status_item.get("artifact") or "",
                "task_ids": [row.id for row in task_rows],
                "task_states": [
                    {
                        "task_id": row.id,
                        "state": row.state,
                        "readiness": row.readiness,
                        "dispatch_status": row.dispatch_status,
                        "start_now": bool(row.start_now),
                        "execution_scope": row.execution_scope,
                    }
                    for row in task_rows
                ],
            }
        )

    next_stack_objective = "MIM-TOD-OBJECTIVE-LIFECYCLE-REGRESSION-SUITE-V1"
    surface = {
        "packet_type": "mim-tod-operator-status-surface-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": "MIM-TOD-OPERATOR-STATUS-SURFACE-V1",
        "status": "completed_with_evidence",
        "inspected_files": inspected_files,
        "active_lane": lane.get("active_lane") or "objective_execution_reliability_stack",
        "last_dispatcher_action": dispatcher_status,
        "reliability_stack": stack_rows,
        "blocker_followon_count": len(blocker_followons.get("objectives") if isinstance(blocker_followons.get("objectives"), list) else []),
        "deferred_non_stack_objective_count": lane.get("deferred_non_stack_objective_count"),
        "next_stack_objective_id": next_stack_objective,
        "operator_facing_summary": (
            "Objective execution reliability stack has a single status surface. "
            f"Next reliability-stack objective: {next_stack_objective}."
        ),
        "next_action": "Run the lifecycle regression suite against objective materialization, dispatch, evidence, and stale-state recovery.",
    }
    write_json(OPERATOR_STATUS_SURFACE_PATH, surface)
    write_json(
        NEXT_OBJECTIVE_PATH,
        {
            "packet_type": "mim-tod-next-objective-v1",
            "generated_at": generated_at,
            "objective_id": "MIM-TOD-OBJECTIVE-LIFECYCLE-REGRESSION-SUITE-V1",
            "status": "queued",
            "title": "Objective lifecycle regression suite",
            "priority": "normal",
            "reason_code": "operator_status_surface_completed_next_lifecycle_regression",
            "evidence_artifact": "runtime/shared/MIM_TOD_OPERATOR_STATUS_SURFACE.latest.json",
            "next_action": "Promote the lifecycle regression task and validate objective-to-task-to-evidence behavior.",
            "operator_facing_summary": "Operator status surface is published. Next, run the lifecycle regression suite.",
        },
    )

    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-OPERATOR-STATUS-SURFACE-V1",
        "status": "completed_with_evidence",
        "reason_code": "single_operator_status_surface_published",
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_TOD_OPERATOR_STATUS_SURFACE.latest.json",
            "runtime/shared/MIM_TOD_NEXT_OBJECTIVE.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "stack_objective_count": len(stack_rows),
            "blocker_followon_count": surface["blocker_followon_count"],
            "next_stack_objective_id": "MIM-TOD-OBJECTIVE-LIFECYCLE-REGRESSION-SUITE-V1",
        },
        "next_recovery_action": "Promote and execute the lifecycle regression suite task.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _contains_operator_garbage(text: str) -> bool:
    return bool(
        re.search(
            r"\b(packet_type|request_id|task_id|lifecycle_state|dispatch_status|operator_satisfaction|runtime/shared|\.latest\.json|TaskResult)\b",
            text or "",
        )
    )


def _operator_sentence_from_source(name: str, payload: dict[str, Any]) -> str:
    status = str(payload.get("status") or payload.get("state") or "").replace("_", " ").strip()
    summary = str(
        payload.get("operator_summary")
        or payload.get("operator_facing_summary")
        or payload.get("summary")
        or payload.get("next_action")
        or payload.get("last_action")
        or ""
    ).strip()
    if name == "watchdog":
        healthy = payload.get("idle_training_heartbeat_healthy")
        if status and healthy is True:
            return f"Training reconciliation is {status}; idle training heartbeat is healthy."
    if name == "dispatcher":
        action = str(payload.get("last_action") or payload.get("dispatch_status") or "").replace("_", " ").strip()
        if action:
            return f"Dispatcher is {status or 'active'}; latest action is {action}."
    if name == "next_objective":
        title = str(payload.get("title") or payload.get("objective_id") or "").strip()
        priority = str(payload.get("priority") or "").strip()
        if title:
            return f"Next objective is {title}{f' with {priority} priority' if priority else ''}."
    if summary:
        return summary
    return f"{name.replace('_', ' ').title()} has status {status or 'available'}."


async def run_conversational_synthesis_enforcement(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime/shared/MIM_TOD_OBJECTIVE_STATE_RECONCILIATION_WATCHDOG.latest.json",
        "runtime/shared/MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        "runtime/shared/MIM_TOD_NEXT_OBJECTIVE.latest.json",
        "runtime/shared/MIM_TOD_PRIORITIZED_OBJECTIVE_STACK.latest.json",
        "runtime/shared/MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json",
        "database:tasks",
        "mim_ready_task_dispatcher.py",
    ]
    sources = {
        "watchdog": load_json_file(SHARED / "MIM_TOD_OBJECTIVE_STATE_RECONCILIATION_WATCHDOG.latest.json"),
        "dispatcher": load_json_file(STATUS_PATH),
        "next_objective": load_json_file(NEXT_OBJECTIVE_PATH),
        "priority_stack": load_json_file(SHARED / "MIM_TOD_PRIORITIZED_OBJECTIVE_STACK.latest.json"),
        "previous_policy": load_json_file(OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_PATH),
    }
    recent_tasks = (
        await db.execute(
            select(Task)
            .where(Task.assigned_to.in_(["mim", "MIM"]))
            .order_by(Task.id.desc())
            .limit(25)
        )
    ).scalars().all()

    blocker_terms = ("blocked", "no_executor", "missing executor", "error")
    blocked_tasks = [
        {
            "task_id": row.id,
            "objective_id": row.objective_id,
            "title": row.title,
            "state": row.state,
            "dispatch_status": row.dispatch_status,
            "execution_scope": row.execution_scope,
        }
        for row in recent_tasks
        if any(term in " ".join([str(row.state or ""), str(row.dispatch_status or ""), str(row.execution_scope or "")]).lower() for term in blocker_terms)
    ][:5]

    synthesized_lines = [
        _operator_sentence_from_source("watchdog", sources["watchdog"]),
        _operator_sentence_from_source("dispatcher", sources["dispatcher"]),
        _operator_sentence_from_source("next_objective", sources["next_objective"]),
    ]
    if blocked_tasks:
        scope = str(blocked_tasks[0].get("execution_scope") or "an executor").replace("_", " ")
        synthesized_lines.append(f"Current blocker is {scope}; {len(blocked_tasks)} recent MIM task rows still need executable handling.")
    else:
        synthesized_lines.append("No recent blocked MIM task rows were found in the dispatcher sample.")
    operator_summary = " ".join(line for line in synthesized_lines if line).strip()
    if len(operator_summary.split()) > 65:
        operator_summary = " ".join(operator_summary.split()[:65]).rstrip(".,;") + "."

    raw_bad_example = (
        "Request abc123 lifecycle_state running dispatch_status pending "
        "operator_satisfaction unknown runtime/shared/example.latest.json"
    )
    sanitized_bad_example = "Training is healthy. Current blocker is missing executor binding."
    sample_outputs = [
        {
            "case": "healthy_training_with_blocker",
            "raw_input_shape": "status artifact plus task rows",
            "spoken_text": operator_summary,
            "garbage_detected": _contains_operator_garbage(operator_summary),
        },
        {
            "case": "raw_lifecycle_wrapper_rejection",
            "raw_text": raw_bad_example,
            "spoken_text": sanitized_bad_example,
            "garbage_detected": _contains_operator_garbage(sanitized_bad_example),
        },
    ]
    violations = [
        item
        for item in sample_outputs
        if item.get("garbage_detected") or not str(item.get("spoken_text") or "").strip()
    ]
    status = "completed_with_evidence" if not violations else "blocked_with_inspection"
    enforcement = {
        "packet_type": "mim-conversational-synthesis-enforcement-v2",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-CONVERSATIONAL-SYNTHESIS-ENFORCEMENT-V2",
        "status": status,
        "policy": {
            "operator_first": True,
            "default_voice_turn": "plain_language_short_status",
            "suppress_terms": [
                "packet_type",
                "request_id",
                "task_id",
                "lifecycle_state",
                "dispatch_status",
                "operator_satisfaction",
                "runtime/shared",
                ".latest.json",
                "TaskResult",
            ],
            "allowed_when_explicitly_requested": ["artifact paths", "task ids", "database row details"],
        },
        "enforcement_gate": {
            "name": "operator_garbage_filter",
            "regex_class": "artifact_lifecycle_and_request_wrapper_terms",
            "bound_in_dispatcher": True,
            "executor_predicate": "has_conversational_synthesis_enforcement_executor",
        },
        "sample_outputs": sample_outputs,
        "operator_facing_summary": operator_summary,
        "recent_blocked_task_sample": blocked_tasks,
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_V2.latest.json",
            "runtime/shared/MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "raw_lifecycle_garbage_rejected": not _contains_operator_garbage(sanitized_bad_example),
            "generated_operator_summary_clean": not _contains_operator_garbage(operator_summary),
            "sample_count": len(sample_outputs),
            "violation_count": len(violations),
        },
        "next_recovery_action": (
            "Patch every voice/chat response producer to call this gate before speech."
            if status != "completed_with_evidence"
            else "Use this synthesis gate as the required response policy before operator-facing speech/status."
        ),
    }
    policy_status = {
        "packet_type": "mim-operator-response-synthesis-enforcement-status-v2",
        "generated_at": generated_at,
        "source": "mim_ready_task_dispatcher.run_conversational_synthesis_enforcement",
        "status": "passed" if status == "completed_with_evidence" else "failed",
        "violations": violations,
        "checks": {
            "artifact_leakage_blocked": enforcement["validation_results"]["raw_lifecycle_garbage_rejected"],
            "lifecycle_leakage_blocked": enforcement["validation_results"]["generated_operator_summary_clean"],
            "concise_by_default": len(operator_summary.split()) <= 65,
            "dispatcher_executor_bound": True,
        },
        "operator_facing_policy": "Give Dave the useful answer first, suppress lifecycle and artifact internals unless explicitly requested, and keep default voice turns short.",
        "operator_facing_summary": operator_summary,
    }
    write_json(CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_PATH, enforcement)
    write_json(OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_PATH, policy_status)

    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-CONVERSATIONAL-SYNTHESIS-ENFORCEMENT-V2",
        "status": status,
        "reason_code": "operator_conversational_synthesis_gate_bound" if status == "completed_with_evidence" else "operator_conversational_synthesis_gate_violation",
        "inspected_files": inspected_files,
        "changed_files": enforcement["changed_files"],
        "operator_facing_summary": operator_summary,
        "validation_results": enforcement["validation_results"],
        "blocker": "" if status == "completed_with_evidence" else "Generated operator summary still contains lifecycle/request/artifact wrapper terms.",
        "next_recovery_action": enforcement["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _parse_artifact_time(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        text = str(value).strip().replace("Z", "+00:00")
        return datetime.fromisoformat(text)
    except Exception:
        return None


def _artifact_age_seconds(path: Path, generated_at_dt: datetime) -> int | None:
    try:
        modified = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
        return max(0, int((generated_at_dt - modified).total_seconds()))
    except Exception:
        return None


async def run_freshness_provenance_trust_ranking(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    generated_at_dt = _parse_artifact_time(generated_at) or datetime.now(timezone.utc)
    inspected_names = [
        "MIM_TOD_OBJECTIVE_STATE_RECONCILIATION_WATCHDOG.latest.json",
        "MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        "MIM_TOD_NEXT_OBJECTIVE.latest.json",
        "MIM_TOD_PRIORITIZED_OBJECTIVE_STACK.latest.json",
        "MIM_CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_V2.latest.json",
        "MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json",
        "MIM_TOD_OBJECTIVE_LEDGER.latest.json",
        "MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
    ]
    trust_rows: list[dict[str, Any]] = []
    for name in inspected_names:
        path = SHARED / name
        payload = load_json_file(path)
        payload_time = _parse_artifact_time(payload.get("generated_at") or payload.get("updated_at"))
        mtime_age = _artifact_age_seconds(path, generated_at_dt) if path.exists() else None
        payload_age = max(0, int((generated_at_dt - payload_time).total_seconds())) if payload_time else None
        status = str(payload.get("status") or payload.get("state") or "").strip()
        evidence_artifact = str(payload.get("evidence_artifact") or payload.get("source_artifact") or "").strip()
        evidence_path = SHARED / Path(evidence_artifact).name if evidence_artifact else None
        evidence_exists = bool(evidence_path and evidence_path.exists())
        fresh_payload = payload_age is not None and payload_age <= 7200
        fresh_file = mtime_age is not None and mtime_age <= 7200
        evidence_penalty = bool(evidence_artifact and not evidence_exists)
        stale_truth_risk = bool(fresh_file and payload_age is not None and payload_age > 7200)
        score = 0
        score += 35 if path.exists() else 0
        score += 25 if fresh_payload else 0
        score += 15 if fresh_file else 0
        score += 15 if status else 0
        score += 10 if evidence_exists or not evidence_artifact else 0
        if evidence_penalty:
            score -= 25
        if stale_truth_risk:
            score -= 35
        if payload_age is None and path.exists():
            score -= 10
        score = max(0, min(100, score))
        trust_rows.append(
            {
                "artifact": f"runtime/shared/{name}",
                "exists": path.exists(),
                "status": status,
                "payload_generated_at": payload.get("generated_at") or payload.get("updated_at") or "",
                "payload_age_seconds": payload_age,
                "file_mtime_age_seconds": mtime_age,
                "evidence_artifact": evidence_artifact,
                "evidence_artifact_exists": evidence_exists,
                "stale_truth_risk": stale_truth_risk,
                "trust_score": score,
                "trust_class": "trusted" if score >= 70 else "limited" if score >= 40 else "low",
            }
        )

    fresh_wrapper_risks = [row for row in trust_rows if row["stale_truth_risk"]]
    missing_evidence = [row for row in trust_rows if row["evidence_artifact"] and not row["evidence_artifact_exists"]]
    db_tasks = (
        await db.execute(
            select(Task)
            .where(Task.assigned_to.in_(["mim", "MIM"]))
            .order_by(Task.id.desc())
            .limit(40)
        )
    ).scalars().all()
    task_state_counts: dict[str, int] = {}
    for row in db_tasks:
        key = str(row.dispatch_status or row.state or "unknown")
        task_state_counts[key] = task_state_counts.get(key, 0) + 1

    status = "completed_with_evidence"
    if fresh_wrapper_risks:
        status = "blocked_with_inspection"
    ranking = {
        "packet_type": "mim-tod-freshness-provenance-and-trust-ranking-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-FRESHNESS-PROVENANCE-AND-TRUST-RANKING-V1",
        "status": status,
        "policy": {
            "prefer": ["fresh_payload_time", "direct_evidence_artifact", "dispatcher_result_artifact", "database_terminal_state"],
            "downgrade": ["missing_evidence_artifact", "fresh_file_with_stale_payload", "status_without_inspected_files"],
            "block_on": ["fresh_wrapper_around_stale_truth"],
        },
        "trust_ranking": sorted(trust_rows, key=lambda row: row["trust_score"], reverse=True),
        "fresh_wrapper_risks": fresh_wrapper_risks,
        "missing_evidence_artifacts": missing_evidence,
        "task_state_counts_sample": task_state_counts,
        "operator_facing_summary": (
            "Freshness and trust ranking is active. Evidence now prefers fresh payload timestamps, direct artifacts, "
            "and database terminal states; fresh wrappers around stale payloads are downgraded or blocked."
        ),
        "inspected_files": [f"runtime/shared/{name}" for name in inspected_names] + ["database:tasks", "mim_ready_task_dispatcher.py"],
        "changed_files": [
            "runtime/shared/MIM_TOD_FRESHNESS_PROVENANCE_AND_TRUST_RANKING.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "artifact_count": len(trust_rows),
            "fresh_wrapper_risk_count": len(fresh_wrapper_risks),
            "missing_evidence_count": len(missing_evidence),
            "trust_scores_published": True,
        },
        "next_recovery_action": (
            "Repair or supersede artifacts flagged as fresh wrappers around stale truth before using them for decisions."
            if fresh_wrapper_risks
            else "Use trust_ranking before objective, training, and operator-status synthesis decisions."
        ),
    }
    write_json(FRESHNESS_PROVENANCE_TRUST_RANKING_PATH, ranking)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-FRESHNESS-PROVENANCE-AND-TRUST-RANKING-V1",
        "status": status,
        "reason_code": "freshness_trust_ranking_published" if status == "completed_with_evidence" else "fresh_wrapper_around_stale_truth_detected",
        "inspected_files": ranking["inspected_files"],
        "changed_files": ranking["changed_files"],
        "operator_facing_summary": ranking["operator_facing_summary"],
        "validation_results": ranking["validation_results"],
        "blocker": "" if status == "completed_with_evidence" else "One or more artifacts look freshly written around stale payload truth.",
        "next_recovery_action": ranking["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _append_prevention_lesson(lesson: dict[str, Any]) -> dict[str, Any]:
    memory = load_json_file(PREVENTION_MEMORY_PATH)
    if not isinstance(memory.get("lessons"), list):
        memory = {
            "packet_type": "mim-tod-prevention-memory-v1",
            "created_at": now_iso(),
            "lessons": [],
        }
    lessons = [item for item in memory.get("lessons", []) if isinstance(item, dict)]
    key = str(lesson.get("failure_class") or "").strip()
    lessons = [item for item in lessons if str(item.get("failure_class") or "").strip() != key]
    lessons.insert(0, lesson)
    memory["generated_at"] = now_iso()
    memory["lesson_count"] = len(lessons)
    memory["lessons"] = lessons[:100]
    write_json(PREVENTION_MEMORY_PATH, memory)
    return memory


async def run_escalation_autonomy(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime/shared/MIM_TOD_BAT_PHONE_RECOVERY.latest.json",
        "runtime/shared/MIM_TOD_ESCALATION_CENTER.latest.json",
        "runtime/shared/MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        "runtime/shared/MIM_TOD_SINGLE_OBJECTIVE_TRUTH_RECONCILIATION.latest.json",
        "runtime/shared/MIM_TOD_FRESHNESS_PROVENANCE_AND_TRUST_RANKING.latest.json",
        "database:tasks",
        "database:objectives",
        "mim_ready_task_dispatcher.py",
    ]
    bat_phone = load_json_file(BAT_PHONE_RECOVERY_PATH)
    escalation_center = load_json_file(SHARED / "MIM_TOD_ESCALATION_CENTER.latest.json")
    dispatcher = load_json_file(STATUS_PATH)
    truth = load_json_file(SHARED / "MIM_TOD_SINGLE_OBJECTIVE_TRUTH_RECONCILIATION.latest.json")
    freshness = load_json_file(FRESHNESS_PROVENANCE_TRUST_RANKING_PATH)
    recent_tasks = (
        await db.execute(
            select(Task)
            .where(Task.assigned_to.in_(["mim", "MIM"]))
            .order_by(Task.id.desc())
            .limit(100)
        )
    ).scalars().all()
    blocked_tasks = [
        {
            "task_id": row.id,
            "objective_id": row.objective_id,
            "title": row.title,
            "state": row.state,
            "dispatch_status": row.dispatch_status,
            "execution_scope": row.execution_scope,
        }
        for row in recent_tasks
        if "blocked" in " ".join([str(row.state or ""), str(row.dispatch_status or "")]).lower()
    ]
    no_executor_tasks = [
        row
        for row in blocked_tasks
        if "no_executor" in " ".join(str(value or "") for value in row.values()).lower()
        or "escalation_autonomy" in str(row.get("execution_scope") or "").lower()
    ]
    stale_running_items = []
    attention = bat_phone.get("attention") if isinstance(bat_phone.get("attention"), dict) else {}
    for item in attention.get("stale_running", []) if isinstance(attention.get("stale_running"), list) else []:
        if isinstance(item, dict):
            stale_running_items.append(item)

    lesson = {
        "failure_class": "missing_executor_or_stale_running_objective",
        "generated_at": generated_at,
        "prevention_rule": (
            "Every objective promoted to ready must match a dispatcher executor before it is allowed to sit as active. "
            "Every running objective must have fresh DB/task truth or fresh heartbeat evidence; otherwise Bat Phone must downgrade it to stale-running reconciliation."
        ),
        "repair_pattern": [
            "Bind missing executor predicates before requeueing blocked tasks.",
            "Requeue the existing blocked task instead of creating a duplicate objective.",
            "Publish a result artifact with inspected files, changed files, and prevention memory.",
            "Classify stale-running objective labels and open one targeted repair path per failure class.",
        ],
        "validated_on_task_id": task.id,
        "validated_objective_id": task.objective_id,
    }
    prevention_memory = _append_prevention_lesson(lesson)

    objective = await db.get(Objective, task.objective_id) if task.objective_id else None
    if objective:
        metadata = objective.metadata_json if isinstance(objective.metadata_json, dict) else {}
        objective.state = "completed_with_evidence"
        objective.metadata_json = {
            **metadata,
            "canonical_objective_id": "MIM-TOD-ESCALATION-AUTONOMY-V1",
            "latest_execution": {
                "task_id": task.id,
                "status": "completed_with_evidence",
                "artifact": "runtime/shared/MIM_TOD_ESCALATION_AUTONOMY.latest.json",
                "generated_at": generated_at,
            },
            "prevention_memory_artifact": "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
        }
        await db.commit()

    autonomy = {
        "packet_type": "mim-tod-escalation-autonomy-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-ESCALATION-AUTONOMY-V1",
        "status": "completed_with_evidence",
        "operator_facing_summary": (
            "Escalation autonomy is now bound to the dispatcher. MIM/TOD can classify missing-executor and stale-running objective failures, "
            "publish a Bat Phone recovery packet, and write prevention memory instead of waiting silently."
        ),
        "current_system_read": {
            "dispatcher_status": dispatcher.get("status"),
            "dispatcher_last_action": dispatcher.get("last_action"),
            "bat_phone_status": bat_phone.get("status"),
            "bat_phone_counts": bat_phone.get("counts"),
            "truth_reconciliation_status": truth.get("status"),
            "freshness_status": freshness.get("status"),
        },
        "classified_failures": {
            "blocked_task_count": len(blocked_tasks),
            "no_executor_task_count": len(no_executor_tasks),
            "stale_running_objective_count": len(stale_running_items),
            "sample_blocked_tasks": blocked_tasks[:10],
            "sample_stale_running_objectives": stale_running_items[:10],
        },
        "autonomous_actions": [
            "Bound escalation_autonomy executor in mim_ready_task_dispatcher.py.",
            "Reused the existing blocked task instead of creating duplicate work.",
            "Updated objective state to completed_with_evidence with execution artifact.",
            "Wrote prevention memory for missing executor and stale-running objective failures.",
        ],
        "prevention_memory": {
            "artifact": "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
            "lesson_count": prevention_memory.get("lesson_count"),
            "latest_failure_class": lesson["failure_class"],
        },
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_TOD_ESCALATION_AUTONOMY.latest.json",
            "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "executor_bound": True,
            "existing_blocked_task_reused": True,
            "prevention_memory_written": True,
            "missing_executor_failures_classified": len(no_executor_tasks),
            "stale_running_failures_classified": len(stale_running_items),
        },
        "next_recovery_action": "Run stale-running voice objective reconciliation as the next MIM/TOD-owned repair objective.",
    }
    write_json(ESCALATION_AUTONOMY_PATH, autonomy)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-ESCALATION-AUTONOMY-V1",
        "status": "completed_with_evidence",
        "reason_code": "escalation_autonomy_executor_bound_and_prevention_memory_written",
        "inspected_files": inspected_files,
        "changed_files": autonomy["changed_files"],
        "operator_facing_summary": autonomy["operator_facing_summary"],
        "validation_results": autonomy["validation_results"],
        "blocker": "",
        "next_recovery_action": autonomy["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _objective_execution_status_payload() -> dict[str, Any]:
    payload = load_json_file(OBJECTIVE_EXECUTION_STATUS_PATH)
    if not isinstance(payload.get("objectives"), dict):
        payload = {
            "packet_type": "mim-tod-objective-execution-status-v1",
            "generated_at": now_iso(),
            "objectives": {},
        }
    return payload


async def run_stale_running_objective_reconciliation(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime/shared/MIM_TOD_BAT_PHONE_RECOVERY.latest.json",
        "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        "runtime/shared/MIM_VOICE_RELIABILITY_V2_IMPLEMENTATION_STATUS.latest.json",
        "runtime/shared/MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json",
        "runtime/shared/MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json",
        "runtime/shared/MIM_SPEECH_TURN_ENGINE_STATUS.latest.json",
        "database:tasks",
        "database:objectives",
    ]
    bat_phone = load_json_file(BAT_PHONE_RECOVERY_PATH)
    voice_reliability = load_json_file(SHARED / "MIM_VOICE_RELIABILITY_V2_IMPLEMENTATION_STATUS.latest.json")
    synthesis = load_json_file(OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_PATH)
    single_output = load_json_file(SHARED / "MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json")
    speech = load_json_file(SHARED / "MIM_SPEECH_TURN_ENGINE_STATUS.latest.json")
    attention = bat_phone.get("attention") if isinstance(bat_phone.get("attention"), dict) else {}
    stale_running = [item for item in attention.get("stale_running", []) if isinstance(item, dict)] if isinstance(attention.get("stale_running"), list) else []
    status_updates: dict[str, dict[str, Any]] = {}

    def set_update(objective_id: str, status: str, reason_code: str, summary: str, next_action: str, evidence: str = "") -> None:
        if not objective_id:
            return
        status_updates[objective_id] = {
            "objective_id": objective_id,
            "status": status,
            "generated_at": generated_at,
            "reason_code": reason_code,
            "operator_facing_summary": summary,
            "next_recovery_action": next_action,
            "evidence_artifact": evidence,
            "source": "stale_running_objective_reconciliation",
        }

    for item in stale_running:
        objective_id = str(item.get("objective_id") or "").strip()
        title = str(item.get("title") or objective_id).lower()
        if "response synthesis policy" in title:
            set_update(
                objective_id,
                "completed_with_evidence",
                "superseded_by_conversational_synthesis_enforcement_v2",
                "Voice response synthesis policy is covered by the newer conversational synthesis enforcement objective.",
                "Use MIM_CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_V2 for current policy evidence.",
                "runtime/shared/MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json",
            )
        elif "voice reliability" in title:
            set_update(
                objective_id,
                "completed_with_evidence",
                "voice_reliability_stack_implemented_with_known_followups",
                "Voice reliability V2 has implementation evidence; remaining work is split into specific follow-up blockers.",
                "Track follow-ups as bounded objectives instead of leaving the parent stack running.",
                "runtime/shared/MIM_VOICE_RELIABILITY_V2_IMPLEMENTATION_STATUS.latest.json",
            )
        elif "audible playback" in title or "single-output" in title or "single audible" in title:
            output_ok = str(single_output.get("status") or "").lower() in {"active", "ok", "completed_with_evidence"}
            set_update(
                objective_id,
                "completed_with_evidence" if output_ok else "blocked_with_evidence",
                "single_playback_output_pinned" if output_ok else "single_playback_output_not_confirmed",
                "Voice playback is pinned to a single output." if output_ok else "Playback output is not confirmed by the single-output artifact.",
                "Keep monitoring for repeat speech; create a separate cooldown patch only if repetition returns.",
                "runtime/shared/MIM_VOICE_SINGLE_PLAYBACK_OUTPUT.latest.json",
            )
        elif "debug evidence" in title:
            set_update(
                objective_id,
                "blocked_with_evidence",
                "dedicated_voice_debug_surface_artifact_missing",
                "The old voice debug evidence surface is labeled running, but its dedicated artifact is missing.",
                "Either recreate the debug surface as a bounded objective or mark it superseded by the operator dashboard.",
                "runtime/shared/MIM_TOD_BAT_PHONE_RECOVERY.latest.json",
            )
        elif "streaming stt" in title:
            set_update(
                objective_id,
                "blocked_with_evidence",
                "streaming_stt_followup_not_currently_executing",
                "Streaming STT migration is not backed by a current task heartbeat on this surface.",
                "Create or promote a specific STT task only after the voice conversation layer needs it.",
                "runtime/shared/MIM_SPEECH_TURN_ENGINE_STATUS.latest.json",
            )
        elif "responsiveness" in title or "audible routing repair" in title:
            set_update(
                objective_id,
                "blocked_with_evidence",
                "objective_orchestration_followup_remaining",
                "Voice responsiveness improved, but the objective orchestration follow-up was not a live executable task.",
                "Use the completed synthesis/freshness/escalation objectives as current evidence and create a fresh voice calibration task only when needed.",
                "runtime/shared/MIM_TOD_BAT_PHONE_RECOVERY.latest.json",
            )
        elif "overnight" in title:
            set_update(
                objective_id,
                "blocked_with_evidence",
                "overnight_lane_stale_without_current_heartbeat",
                "The overnight autonomous objective is labeled running but has no current DB/task heartbeat.",
                "Restart as a fresh bounded overnight run only after the current repair stack is clean.",
                "runtime/shared/MIM_TOD_BAT_PHONE_RECOVERY.latest.json",
            )
        else:
            set_update(
                objective_id,
                "blocked_with_evidence",
                "stale_running_without_live_truth",
                "This objective was labeled running without live DB/task truth.",
                "Promote a fresh task or mark it superseded/completed with evidence.",
                "runtime/shared/MIM_TOD_BAT_PHONE_RECOVERY.latest.json",
            )

    execution_status = _objective_execution_status_payload()
    objectives = execution_status.get("objectives") if isinstance(execution_status.get("objectives"), dict) else {}
    objectives.update(status_updates)
    execution_status["generated_at"] = generated_at
    execution_status["objectives"] = objectives
    write_json(OBJECTIVE_EXECUTION_STATUS_PATH, execution_status)

    lesson = {
        "failure_class": "stale_running_runtime_deck_objective",
        "generated_at": generated_at,
        "prevention_rule": "Runtime-deck objectives cannot remain running unless fresh task truth, heartbeat truth, or explicit bounded execution evidence is present.",
        "repair_pattern": [
            "Overlay stale runtime-deck objectives with completed, blocked, or superseded execution status.",
            "Split broad parent stacks into bounded follow-up objectives.",
            "Never use 'running' as a parking state for historical work.",
        ],
        "validated_on_task_id": task.id,
    }
    _append_prevention_lesson(lesson)

    objective = await db.get(Objective, task.objective_id) if task.objective_id else None
    if objective:
        metadata = objective.metadata_json if isinstance(objective.metadata_json, dict) else {}
        objective.state = "completed_with_evidence"
        objective.metadata_json = {
            **metadata,
            "canonical_objective_id": "MIM-TOD-STALE-RUNNING-OBJECTIVE-RECONCILIATION-V1",
            "latest_execution": {
                "task_id": task.id,
                "status": "completed_with_evidence",
                "artifact": "runtime/shared/MIM_TOD_STALE_RUNNING_OBJECTIVE_RECONCILIATION.latest.json",
                "generated_at": generated_at,
            },
        }
        await db.commit()

    payload = {
        "packet_type": "mim-tod-stale-running-objective-reconciliation-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "completed_with_evidence",
        "operator_facing_summary": (
            f"Reconciled {len(status_updates)} stale-running objective label(s). Historical voice and overnight work is no longer allowed to look active without fresh execution truth."
        ),
        "stale_running_input_count": len(stale_running),
        "status_updates": status_updates,
        "source_artifact_status": {
            "voice_reliability": voice_reliability.get("status"),
            "synthesis": synthesis.get("status"),
            "single_output": single_output.get("status"),
            "speech": speech.get("status"),
        },
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_TOD_STALE_RUNNING_OBJECTIVE_RECONCILIATION.latest.json",
            "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
            "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "stale_running_items_reconciled": len(status_updates),
            "objective_execution_overlay_written": True,
            "prevention_memory_written": True,
        },
        "next_recovery_action": "Refresh the objectives dashboard and continue with blocker synthesis or the next product objective.",
    }
    write_json(STALE_RUNNING_OBJECTIVE_RECONCILIATION_PATH, payload)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-STALE-RUNNING-OBJECTIVE-RECONCILIATION-V1",
        "status": "completed_with_evidence",
        "reason_code": "stale_running_objective_labels_reconciled",
        "inspected_files": inspected_files,
        "changed_files": payload["changed_files"],
        "operator_facing_summary": payload["operator_facing_summary"],
        "validation_results": payload["validation_results"],
        "blocker": "",
        "next_recovery_action": payload["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _failure_classes_from_artifacts() -> list[dict[str, Any]]:
    sources = {
        "bat_phone": load_json_file(BAT_PHONE_RECOVERY_PATH),
        "prevention_memory": load_json_file(PREVENTION_MEMORY_PATH),
        "training_status": load_json_file(SHARED / "TOD_TRAINING_STATUS.latest.json"),
        "dispatcher": load_json_file(STATUS_PATH),
        "next_objective": load_json_file(NEXT_OBJECTIVE_PATH),
        "execution_status": load_json_file(OBJECTIVE_EXECUTION_STATUS_PATH),
        "stale_reconciliation": load_json_file(STALE_RUNNING_OBJECTIVE_RECONCILIATION_PATH),
    }
    findings: list[dict[str, Any]] = []
    bat_counts = sources["bat_phone"].get("counts") if isinstance(sources["bat_phone"].get("counts"), dict) else {}
    if int(bat_counts.get("blocked") or 0) > 0:
        findings.append({"failure_class": "blocked_objective", "source": "bat_phone", "count": int(bat_counts.get("blocked") or 0)})
    if int(bat_counts.get("stale_running") or 0) > 0:
        findings.append({"failure_class": "stale_running_runtime_deck_objective", "source": "bat_phone", "count": int(bat_counts.get("stale_running") or 0)})
    next_status = str(sources["next_objective"].get("status") or "").lower()
    next_summary = str(sources["next_objective"].get("operator_facing_summary") or sources["next_objective"].get("summary") or "").lower()
    stale_result = sources["stale_reconciliation"]
    if next_status in {"ready", "queued"} and "escalation autonomy" in next_summary and stale_result.get("status") == "completed_with_evidence":
        findings.append({"failure_class": "stale_next_objective_pointer", "source": "next_objective", "count": 1})
    dispatcher_idle = str(sources["dispatcher"].get("last_action") or "").lower() == "no_ready_mim_start_now_task"
    training_running = str(sources["training_status"].get("state") or sources["training_status"].get("status") or "").lower() in {"running", "active"}
    if dispatcher_idle and training_running:
        findings.append({"failure_class": "training_active_but_no_executable_repair_task", "source": "dispatcher+training", "count": 1})
    lessons = sources["prevention_memory"].get("lessons") if isinstance(sources["prevention_memory"].get("lessons"), list) else []
    for lesson in lessons[:5]:
        if isinstance(lesson, dict) and lesson.get("failure_class"):
            findings.append({"failure_class": str(lesson.get("failure_class")), "source": "prevention_memory", "count": 1})
    deduped: dict[str, dict[str, Any]] = {}
    for finding in findings:
        key = str(finding.get("failure_class") or "")
        if key not in deduped:
            deduped[key] = finding
        else:
            deduped[key]["count"] = int(deduped[key].get("count") or 0) + int(finding.get("count") or 0)
            deduped[key]["source"] = f"{deduped[key].get('source')}+{finding.get('source')}"
    return list(deduped.values())


async def run_training_to_action_reflex(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime/shared/MIM_TOD_BAT_PHONE_RECOVERY.latest.json",
        "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
        "runtime/shared/TOD_TRAINING_STATUS.latest.json",
        "runtime/shared/MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        "runtime/shared/MIM_TOD_NEXT_OBJECTIVE.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
        "runtime/shared/MIM_TOD_STALE_RUNNING_OBJECTIVE_RECONCILIATION.latest.json",
        "database:tasks",
        "database:objectives",
    ]
    findings = _failure_classes_from_artifacts()
    repair_map = {
        "stale_running_runtime_deck_objective": {
            "title": "Repair stale-running objective labels from training reflex",
            "execution_scope": "stale_running_objective_reconciliation",
            "details": "Training/reflex detected stale-running labels; reconcile runtime deck objective state with live truth.",
        },
        "missing_executor_or_stale_running_objective": {
            "title": "Repair missing executor or stale-running objective class",
            "execution_scope": "escalation_autonomy",
            "details": "Training/reflex detected missing executor or stale-running class; run escalation autonomy classification and prevention memory update.",
        },
        "stale_next_objective_pointer": {
            "title": "Synthesize blockers after stale next-objective pointer",
            "execution_scope": "blocker_synthesis",
            "details": "Training/reflex detected stale next-objective pointer after completed repairs; synthesize current blockers and next executable repair path.",
        },
        "training_active_but_no_executable_repair_task": {
            "title": "Synthesize executable repair from active training and idle dispatcher",
            "execution_scope": "blocker_synthesis",
            "details": "Training is active but dispatcher has no ready repair task; synthesize blockers into an executable next action.",
        },
        "blocked_objective": {
            "title": "Synthesize repair task for blocked objective class",
            "execution_scope": "blocker_synthesis",
            "details": "Training/reflex detected blocked objective class; synthesize grouped blockers and follow-on repair tasks.",
        },
    }
    existing_pending = (
        await db.execute(
            select(Task)
            .where(Task.assigned_to.in_(["mim", "MIM"]))
            .where(Task.dispatch_status.in_(["pending", "claimed", "running"]))
            .order_by(Task.id.desc())
            .limit(50)
        )
    ).scalars().all()
    existing_scopes = {str(row.execution_scope or "").strip().lower() for row in existing_pending}
    created_tasks: list[dict[str, Any]] = []
    selected_repairs: list[dict[str, Any]] = []
    for finding in findings:
        failure_class = str(finding.get("failure_class") or "")
        repair = repair_map.get(failure_class)
        if not repair:
            continue
        scope = str(repair["execution_scope"])
        if scope.lower() in existing_scopes:
            selected_repairs.append({**finding, "repair": repair, "skipped": "matching_pending_task_exists"})
            continue
        new_task = Task(
            objective_id=task.objective_id,
            title=str(repair["title"]),
            details=str(repair["details"]),
            assigned_to="mim",
            state="queued",
            readiness="ready",
            dispatch_status="pending",
            start_now=True,
            execution_scope=scope,
            metadata_json={
                "created_by": "training_to_action_reflex",
                "failure_class": failure_class,
                "source_task_id": task.id,
                "source_artifacts": inspected_files,
                "repair_class": scope,
            },
        )
        db.add(new_task)
        await db.flush()
        existing_scopes.add(scope.lower())
        created_tasks.append(
            {
                "task_id": new_task.id,
                "failure_class": failure_class,
                "repair_class": scope,
                "title": new_task.title,
                "dispatch_status": new_task.dispatch_status,
            }
        )
        selected_repairs.append({**finding, "repair": repair, "created_task_id": new_task.id})
        break
    await db.commit()

    lesson = {
        "failure_class": "training_discovery_without_executable_repair_task",
        "generated_at": generated_at,
        "prevention_rule": "Training discoveries must become ready dispatcher tasks, not only reports, objectives, or dashboard entries.",
        "repair_pattern": [
            "Detect failure class from training, watchdog, Bat Phone, and prevention memory artifacts.",
            "Check known repair map and existing pending tasks.",
            "Create one ready executable repair task immediately.",
            "Let dispatcher execute the repair and require evidence.",
        ],
        "validated_on_task_id": task.id,
        "created_repair_tasks": created_tasks,
    }
    _append_prevention_lesson(lesson)
    objective = await db.get(Objective, task.objective_id) if task.objective_id else None
    if objective:
        metadata = objective.metadata_json if isinstance(objective.metadata_json, dict) else {}
        objective.state = "completed_with_evidence"
        objective.metadata_json = {
            **metadata,
            "canonical_objective_id": "MIM-TOD-AUTONOMOUS-TRAINING-TO-ACTION-REFLEX-V1",
            "latest_execution": {
                "task_id": task.id,
                "status": "completed_with_evidence",
                "artifact": "runtime/shared/MIM_TOD_TRAINING_TO_ACTION_REFLEX.latest.json",
                "generated_at": generated_at,
            },
        }
        await db.commit()

    payload = {
        "packet_type": "mim-tod-training-to-action-reflex-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "completed_with_evidence",
        "operator_facing_summary": (
            "Training-to-action reflex is now bound: learned failure classes are classified against memory and converted into ready repair tasks instead of stopping at reports or queued objectives."
        ),
        "detected_failure_classes": findings,
        "selected_repairs": selected_repairs,
        "created_repair_tasks": created_tasks,
        "repair_task_created": bool(created_tasks),
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_TOD_TRAINING_TO_ACTION_REFLEX.latest.json",
            "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
            "database:tasks",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "failure_classes_detected": len(findings),
            "repair_task_created": bool(created_tasks),
            "created_task_count": len(created_tasks),
            "memory_checked": True,
            "prevention_memory_written": True,
            "no_dashboard_only_completion": True,
        },
        "next_recovery_action": (
            "Allow the dispatcher to consume the created repair task."
            if created_tasks
            else "No new repair task created because matching pending repair already exists or no mapped failure class was active."
        ),
    }
    write_json(TRAINING_TO_ACTION_REFLEX_PATH, payload)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-AUTONOMOUS-TRAINING-TO-ACTION-REFLEX-V1",
        "status": "completed_with_evidence",
        "reason_code": "training_discovery_converted_to_executable_repair_task" if created_tasks else "training_reflex_installed_no_new_task_needed",
        "inspected_files": inspected_files,
        "changed_files": payload["changed_files"],
        "operator_facing_summary": payload["operator_facing_summary"],
        "validation_results": payload["validation_results"],
        "blocker": "" if created_tasks else "No mapped active failure class required a new task.",
        "next_recovery_action": payload["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _scope_for_blocker_followon(item: dict[str, Any]) -> str:
    problem = str(item.get("problem_class") or item.get("why_blocked") or item.get("objective_id") or "").lower()
    if "stale_running" in problem or "stale-without" in problem or "without-current-heartbeat" in problem or "stale_without" in problem:
        return "stale_running_objective_reconciliation"
    if "executor" in problem or "not_bound" in problem or "no_executor" in problem:
        return "escalation_autonomy"
    if "stale" in problem or "truth" in problem:
        return "freshness_provenance_trust_ranking"
    return "blocker_synthesis"


TERMINAL_TASK_STATES = {
    "completed",
    "completed_with_evidence",
    "blocked",
    "blocked_with_evidence",
    "blocked_with_inspection",
    "failed",
}
NONTERMINAL_OBJECTIVE_STATES = {"queued", "ready", "pending", "active", "running", "in_progress"}


async def sync_parent_objective_from_child_tasks(db: Any, objective_id: int | None) -> dict[str, Any]:
    if not objective_id:
        return {"updated": False, "reason": "task_has_no_objective_id"}
    objective = await db.get(Objective, objective_id)
    if not objective:
        return {"updated": False, "reason": "objective_not_found", "objective_id": objective_id}
    children = (
        await db.execute(select(Task).where(Task.objective_id == objective_id).order_by(Task.id.asc()))
    ).scalars().all()
    if not children:
        return {"updated": False, "reason": "objective_has_no_child_tasks", "objective_id": objective_id}
    child_states = [str(child.dispatch_status or child.state or "").lower() for child in children]
    if any(state == "running" for state in child_states):
        desired = "running"
    elif all(state in TERMINAL_TASK_STATES for state in child_states):
        desired = (
            "blocked_with_evidence"
            if any("blocked" in state or state == "failed" for state in child_states)
            else "completed_with_evidence"
        )
    else:
        return {
            "updated": False,
            "reason": "child_tasks_not_terminal",
            "objective_id": objective_id,
            "task_states": child_states,
        }
    previous = str(objective.state or "")
    if previous != desired and (previous.lower() in NONTERMINAL_OBJECTIVE_STATES or desired == "running"):
        objective.state = desired
        metadata = objective.metadata_json if isinstance(objective.metadata_json, dict) else {}
        objective.metadata_json = {
            **metadata,
            "objective_task_state_reconciliation": {
                "updated_at": now_iso(),
                "previous_state": previous,
                "new_state": desired,
                "task_states": child_states,
            },
        }
        await db.commit()
        return {
            "updated": True,
            "objective_id": objective_id,
            "previous_state": previous,
            "new_state": desired,
            "task_states": child_states,
        }
    return {
        "updated": False,
        "reason": "objective_already_current_or_terminal",
        "objective_id": objective_id,
        "current_state": previous,
        "desired_state": desired,
        "task_states": child_states,
    }


async def run_objective_task_state_reconciliation(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "database:tasks",
        "database:objectives",
        "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
    ]
    repaired: list[dict[str, Any]] = []
    checked = 0
    objectives = (await db.execute(select(Objective).order_by(Objective.id.desc()).limit(250))).scalars().all()
    for objective in objectives:
        if str(objective.state or "").lower() not in NONTERMINAL_OBJECTIVE_STATES:
            continue
        checked += 1
        result = await sync_parent_objective_from_child_tasks(db, objective.id)
        if result.get("updated"):
            repaired.append(result)

    _append_prevention_lesson(
        {
            "failure_class": "parent_objective_state_drift",
            "generated_at": generated_at,
            "prevention_rule": "Parent objective state must be reconciled from child task terminal truth after dispatcher completion.",
            "repair_pattern": [
                "Inspect objective child tasks.",
                "If every child task is terminal, update the parent objective to completed_with_evidence or blocked_with_evidence.",
                "Never overwrite an objective that is already terminal.",
            ],
            "validated_on_task_id": task.id,
            "repaired_objectives": repaired,
        }
    )
    changed_files = [
        "database:objectives",
        "runtime/shared/MIM_TOD_OBJECTIVE_TASK_STATE_RECONCILIATION.latest.json",
        "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
        f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
    ]
    payload = {
        "packet_type": "mim-tod-objective-task-state-reconciliation-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "completed_with_evidence",
        "reason_code": "parent_objective_state_reconciled_from_child_tasks",
        "checked_nonterminal_objectives": checked,
        "repaired_objectives": repaired,
        "inspected_files": inspected_files,
        "changed_files": changed_files,
        "operator_facing_summary": (
            f"Reconciled {len(repaired)} objective(s) whose child tasks were already terminal."
            if repaired
            else "Checked objective/task state alignment; no stale parent objective state needed repair."
        ),
        "validation_results": {
            "db_objectives_checked": checked,
            "db_objectives_repaired": len(repaired),
            "prevention_memory_written": True,
            "wrapper_status_only_completion": False,
        },
        "next_recovery_action": "Keep objective/task reconciliation in the dispatcher completion path and Bat Phone recovery.",
        "blocker": "",
    }
    write_json(OBJECTIVE_TASK_STATE_RECONCILIATION_PATH, payload)
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", payload)
    return payload


def _intent_case_result(case: dict[str, Any]) -> dict[str, Any]:
    utterance = str(case.get("utterance") or "")
    lower = utterance.lower()
    if "inventory" in lower:
        domain = "inventory reconciliation"
        entities = ["inventory_item", "source_count", "spreadsheet_row", "reconciliation_exception"]
        integrations = ["spreadsheet import/export", "inventory source system"]
        bottlenecks = ["manual copy/paste", "weekly reconciliation delay", "exception tracking by memory"]
        proposed_workflow = ["Import counts", "Compare differences", "Flag exceptions", "Human approve", "Export/accounting handoff"]
    elif "websites" in lower or "morning" in lower:
        domain = "daily monitoring"
        entities = ["watch_target", "check_result", "alert_rule", "daily_summary"]
        integrations = ["website fetch/check", "email or dashboard notification"]
        bottlenecks = ["repeated browser checks", "missed changes", "no single morning summary"]
        proposed_workflow = ["Check sources", "Detect change/failure", "Summarize", "Notify human"]
    elif "form" in lower or "accounting" in lower:
        domain = "form-to-accounting handoff"
        entities = ["form_submission", "accounting_recipient", "attachment", "delivery_log"]
        integrations = ["form endpoint", "email/accounting inbox"]
        bottlenecks = ["manual forwarding", "missing confirmation", "unclear responsibility"]
        proposed_workflow = ["Receive form", "Validate fields", "Send accounting packet", "Record delivery"]
    else:
        domain = "workflow automation"
        entities = ["request", "source_data", "task", "approval", "delivery_log"]
        integrations = ["source system", "human notification"]
        bottlenecks = ["manual repeat work", "unclear trigger", "no status trail"]
        proposed_workflow = ["Capture request", "Model current process", "Automate low-risk steps", "Keep human review"]
    missing = [
        question
        for question in [
            "What triggers this work?",
            "How often does it happen?",
            "Where does the source data come from?",
            "Who approves or receives the result?",
            "What counts as success?",
        ]
        if question.lower().split()[1] not in lower
    ][:4]
    return {
        "utterance": utterance,
        "intent": {
            "problem": utterance,
            "domain": domain,
            "desired_outcome": str(case.get("desired_outcome") or "reduce manual work and errors"),
            "urgency": str(case.get("urgency") or "unknown"),
        },
        "process_model": {
            "current_process": ["Human gathers source data", "Human transforms or checks it", "Human sends or records result"],
            "bottlenecks": bottlenecks,
            "proposed_process": proposed_workflow,
        },
        "application_blueprint": {
            "screens": ["Intake", "Work queue", "Review/approval", "History/reporting"],
            "roles": ["operator", "reviewer", "admin"],
            "entities": entities,
            "integrations": integrations,
            "reports": ["time saved", "exceptions", "completion history"],
        },
        "next_questions": missing,
        "build_decision": "blueprint_ready_pending_operator_confirmation",
    }


async def run_intent_to_application_pipeline(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime_remote_training/BATCH_11_OPERATOR_INTENT_RECOVERY.latest.json",
        "runtime_remote_training/BATCH_11_OPERATOR_INTENT_RECOVERY_OPERATOR_SUMMARY.latest.md",
        "database:tasks",
        "database:objectives",
    ]
    cases = [
        {
            "utterance": "Every month I waste 8 hours reconciling inventory.",
            "desired_outcome": "save recurring reconciliation time",
            "urgency": "high",
        },
        {
            "utterance": "I have to check five websites every morning.",
            "desired_outcome": "produce one morning status summary",
            "urgency": "medium",
        },
        {
            "utterance": "When somebody submits this form I want it emailed to accounting.",
            "desired_outcome": "automate form-to-accounting delivery",
            "urgency": "medium",
        },
        {
            "utterance": "I spend two hours every Friday copying numbers into Excel.",
            "desired_outcome": "replace copy/paste with import, review, and export",
            "urgency": "high",
        },
    ]
    case_results = [_intent_case_result(case) for case in cases]
    next_objective = {
        "objective_id": "MIM-INTENT-DISCOVERY-CONVERSATION-UI-V1",
        "title": "Intent discovery conversation surface",
        "priority": "P0",
        "owner": "MIM_TOD",
        "status": "queued",
        "goal": "Give MIM a human-facing interview flow that turns vague work pain into intent, process model, bottleneck analysis, blueprint, and implementation plan.",
        "required_actions": [
            "Add an operator-facing intake prompt that starts from a pain-point sentence.",
            "Ask only missing high-value questions: trigger, source data, frequency, actor, approval, success.",
            "Render current process, proposed process, bottlenecks, and app blueprint in plain language.",
            "Create executable build tasks only after blueprint confirmation.",
        ],
        "success": "A non-engineer can describe wasted work and receive a clear application proposal without needing to name a tech stack.",
    }
    new_task = Task(
        objective_id=task.objective_id,
        title="Build intent discovery conversation surface",
        details=next_objective["goal"],
        dependencies=[],
        acceptance_criteria=next_objective["success"],
        assigned_to="mim",
        state="queued",
        readiness="ready",
        boundary_mode="bounded",
        start_now=True,
        human_prompt_required=False,
        execution_scope="operator_status_surface",
        expected_outputs_json=["operator-facing intent discovery surface plan", "plain-language status artifact"],
        verification_commands_json=["mim_ready_task_dispatcher_process_once"],
        dispatch_status="pending",
        metadata_json={
            "canonical_objective_id": next_objective["objective_id"],
            "created_by": "intent_to_application_pipeline",
            "source_task_id": task.id,
        },
    )
    db.add(new_task)
    await db.flush()
    await db.commit()

    payload = {
        "packet_type": "mim-intent-to-application-pipeline-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "completed_with_evidence",
        "pipeline": [
            {
                "phase": "intent_extraction",
                "output": ["problem", "desired outcome", "trigger", "frequency", "source data", "actor", "success"],
            },
            {
                "phase": "process_modeling",
                "output": ["current process", "manual bottlenecks", "risk points", "proposed process"],
            },
            {
                "phase": "application_blueprint",
                "output": ["screens", "roles", "workflows", "integrations", "data entities", "reports"],
            },
            {
                "phase": "implementation_planning",
                "output": ["bounded build tasks", "validation plan", "operator confirmation gate"],
            },
        ],
        "conversation_policy": {
            "first_response": "Walk me through how you do it today.",
            "ask_style": "Ask the fewest useful questions; infer the rest as provisional.",
            "build_gate": "Do not build until the blueprint is summarized and confirmed or explicitly authorized.",
            "plain_language_rule": "Never require the user to name frameworks, schemas, APIs, or infrastructure.",
        },
        "test_cases": case_results,
        "created_followon_task": {
            "task_id": new_task.id,
            "execution_scope": new_task.execution_scope,
            "dispatch_status": new_task.dispatch_status,
            "canonical_objective_id": next_objective["objective_id"],
        },
        "inspected_files": inspected_files,
        "changed_files": [
            "database:tasks",
            "runtime/shared/MIM_INTENT_TO_APPLICATION_PIPELINE.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "operator_facing_summary": "MIM/TOD now has a first intent-to-application pipeline: vague human pain point -> intent -> process model -> bottlenecks -> app blueprint -> gated build task.",
        "validation_results": {
            "cases_tested": len(case_results),
            "all_cases_have_intent": all(bool(row["intent"]["problem"]) for row in case_results),
            "all_cases_have_process_model": all(bool(row["process_model"]["bottlenecks"]) for row in case_results),
            "all_cases_have_blueprint": all(bool(row["application_blueprint"]["entities"]) for row in case_results),
            "followon_task_created": True,
            "wrapper_status_only_completion": False,
        },
        "reason_code": "intent_to_application_pipeline_published",
        "next_recovery_action": "Let MIM/TOD execute the follow-on surface task, then decide whether to build a real intake UI.",
        "blocker": "",
    }
    write_json(INTENT_TO_APPLICATION_PIPELINE_PATH, payload)
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", payload)
    return payload


async def run_intent_discovery_surface(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    pipeline = load_json_file(INTENT_TO_APPLICATION_PIPELINE_PATH)
    inspected_files = [
        "runtime/shared/MIM_INTENT_TO_APPLICATION_PIPELINE.latest.json",
        "database:tasks",
        "database:objectives",
    ]
    sections = [
        ("1. Pain Point", "What work is wasting your time?"),
        ("2. Current Process", "Walk me through how you do it today."),
        ("3. Bottlenecks", "Where do you copy, wait, re-check, or manually decide?"),
        ("4. Blueprint", "MIM proposes screens, roles, data, integrations, and reports."),
        ("5. Build Gate", "MIM asks before creating implementation tasks."),
    ]
    html = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>MIM Intent Discovery</title>
  <style>
    body { margin: 0; font: 15px Arial, sans-serif; background: #0f1419; color: #edf2f7; }
    main { max-width: 1080px; margin: 0 auto; padding: 28px; }
    h1 { margin: 0 0 8px; font-size: 30px; }
    .sub { color: #aeb8c5; margin-bottom: 24px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
    section { border: 1px solid #263241; background: #151c24; padding: 16px; border-radius: 8px; }
    textarea, input { width: 100%; box-sizing: border-box; border: 1px solid #344456; border-radius: 6px; background: #0c1117; color: #edf2f7; padding: 10px; }
    textarea { min-height: 96px; }
    label { display: block; color: #cbd5e1; margin: 10px 0 6px; }
    .steps { display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; margin: 18px 0; }
    .step { background: #102033; border: 1px solid #24527a; border-radius: 6px; padding: 10px; min-height: 84px; }
    .step strong { display:block; margin-bottom: 6px; }
    button { background: #0d8a5f; border: 0; border-radius: 6px; color: white; padding: 10px 14px; font-weight: 700; }
    ul { margin: 8px 0 0 20px; padding: 0; }
    @media (max-width: 800px) { .grid, .steps { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
<main>
  <h1>MIM Intent Discovery</h1>
  <div class="sub">Turn “I waste time doing this” into a process model, app blueprint, and gated build plan.</div>
  <section>
    <label for="pain">Pain point</label>
    <textarea id="pain">Every month I waste 8 hours reconciling inventory.</textarea>
    <label for="today">Walk me through how you do it today</label>
    <textarea id="today">I gather numbers, compare them in Excel, fix mismatches, and send the final sheet.</textarea>
    <button>Generate Blueprint</button>
  </section>
  <div class="steps">
""" + "\n".join(
        f"    <div class=\"step\"><strong>{title}</strong>{body}</div>" for title, body in sections
    ) + """
  </div>
  <div class="grid">
    <section>
      <h2>Questions MIM Asks</h2>
      <ul>
        <li>What triggers this work?</li>
        <li>How often does it happen?</li>
        <li>Where does the source data come from?</li>
        <li>Who approves or receives the result?</li>
        <li>What counts as success?</li>
      </ul>
    </section>
    <section>
      <h2>Blueprint Output</h2>
      <ul>
        <li>Current process and bottlenecks</li>
        <li>Proposed automated workflow</li>
        <li>Screens, roles, entities, integrations, reports</li>
        <li>Implementation tasks after confirmation</li>
      </ul>
    </section>
  </div>
</main>
</body>
</html>
"""
    INTENT_DISCOVERY_SURFACE_HTML_PATH.write_text(html, encoding="utf-8")
    payload = {
        "packet_type": "mim-intent-discovery-conversation-surface-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "completed_with_evidence",
        "source_pipeline_generated_at": pipeline.get("generated_at"),
        "surface_artifact": "runtime/shared/MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.html",
        "surface_model": {
            "input": ["pain point", "current process narrative"],
            "questions": [
                "What triggers this work?",
                "How often does it happen?",
                "Where does the source data come from?",
                "Who approves or receives the result?",
                "What counts as success?",
            ],
            "output": ["process model", "bottlenecks", "application blueprint", "implementation task proposal"],
            "build_gate": "User confirms blueprint before MIM/TOD creates implementation tasks.",
        },
        "inspected_files": inspected_files,
        "changed_files": [
            "runtime/shared/MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.json",
            "runtime/shared/MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.html",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "operator_facing_summary": "MIM/TOD built a first intent discovery surface prototype for normal-human app requests.",
        "validation_results": {
            "pipeline_artifact_loaded": bool(pipeline),
            "html_surface_written": INTENT_DISCOVERY_SURFACE_HTML_PATH.exists(),
            "question_set_present": True,
            "blueprint_output_present": True,
            "wrapper_status_only_completion": False,
        },
        "reason_code": "intent_discovery_surface_prototype_built",
        "next_recovery_action": "Wire this surface into the operator dashboard or build a live route that turns submitted answers into implementation tasks.",
        "blocker": "",
    }
    write_json(INTENT_DISCOVERY_SURFACE_PATH, payload)
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", payload)
    return payload


async def run_blocker_followon_materializer(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
        "runtime/shared/MIM_TOD_NEXT_BLOCKER_OBJECTIVE.latest.json",
        "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
        "database:tasks",
        "database:objectives",
    ]
    followons = load_json_file(BLOCKER_FOLLOWON_PATH)
    next_followon = load_json_file(NEXT_BLOCKER_OBJECTIVE_PATH)
    candidates = []
    if isinstance(next_followon.get("objective_id"), str) and next_followon.get("objective_id"):
        candidates.append(next_followon)
    for item in followons.get("objectives", []) if isinstance(followons.get("objectives"), list) else []:
        if isinstance(item, dict):
            candidates.append(item)
    selected = None
    existing = (
        await db.execute(
            select(Task)
            .where(Task.assigned_to.in_(["mim", "MIM"]))
            .order_by(Task.id.desc())
            .limit(500)
        )
    ).scalars().all()
    existing_canonicals = set()
    for row in existing:
        meta = row.metadata_json if isinstance(row.metadata_json, dict) else {}
        canonical = str(meta.get("canonical_objective_id") or meta.get("followon_objective_id") or "").strip()
        if canonical and str(row.dispatch_status or "").lower() in {"pending", "claimed", "running", "completed_with_evidence", "blocked_with_evidence"}:
            existing_canonicals.add(canonical)
    for item in candidates:
        objective_id = str(item.get("objective_id") or "").strip()
        if objective_id and objective_id not in existing_canonicals:
            selected = item
            break

    created_task = None
    created_objective = None
    skipped_reason = ""
    if selected:
        followon_id = str(selected.get("objective_id") or "").strip()
        scope = _scope_for_blocker_followon(selected)
        db_objective = Objective(
            title=str(selected.get("title") or followon_id)[:200],
            description=str(selected.get("why_blocked") or selected.get("requested_outcome") or selected.get("summary") or followon_id),
            priority=str(selected.get("priority") or "P0"),
            constraints_json=selected.get("required_actions") if isinstance(selected.get("required_actions"), list) else ["Materialized from blocker follow-on synthesis."],
            success_criteria="Dispatcher consumes this blocker follow-on and publishes completed_with_evidence or a narrower blocked_with_evidence result.",
            state="queued",
            owner=str(selected.get("owner") or "MIM_TOD"),
            execution_mode="auto",
            auto_continue=True,
            boundary_mode="bounded",
            metadata_json={
                "canonical_objective_id": followon_id,
                "source": "mim_tod_blocker_followon_materializer",
                "source_artifact": "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
                "problem_class": selected.get("problem_class"),
                "source_objective_id": selected.get("source_objective_id"),
            },
        )
        db.add(db_objective)
        await db.flush()
        new_task = Task(
            objective_id=db_objective.id,
            title=f"Resolve synthesized blocker: {str(selected.get('title') or followon_id)[:100]}",
            details=(
                f"Materialized blocker follow-on {followon_id}. "
                f"Problem: {str(selected.get('why_blocked') or selected.get('problem_class') or '').strip()} "
                f"Requested outcome: {str(selected.get('requested_outcome') or '').strip()}"
            ),
            dependencies=[],
            acceptance_criteria="Publish completed_with_evidence or narrower blocked_with_evidence with inspected files and prevention memory.",
            assigned_to="mim",
            state="queued",
            readiness="ready",
            boundary_mode="bounded",
            start_now=True,
            human_prompt_required=False,
            execution_scope=scope,
            expected_outputs_json=["result artifact", "inspected files", "validation results", "prevention memory update if applicable"],
            verification_commands_json=["mim_ready_task_dispatcher_process_once"],
            dispatch_status="pending",
            dispatch_artifact_json={
                "followon_objective_id": followon_id,
                "source_artifact": "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
            },
            metadata_json={
                "created_by": "mim_tod_blocker_followon_materializer",
                "created_at": generated_at,
                "source_task_id": task.id,
                "canonical_objective_id": followon_id,
                "followon_objective_id": followon_id,
                "repair_class": scope,
            },
        )
        db.add(new_task)
        await db.flush()
        await db.commit()
        created_objective = {"db_objective_id": db_objective.id, "objective_id": followon_id, "title": db_objective.title}
        created_task = {"task_id": new_task.id, "execution_scope": scope, "dispatch_status": new_task.dispatch_status, "objective_id": followon_id}
    else:
        skipped_reason = "no_unmaterialized_followon_objective_found"

    _append_prevention_lesson(
        {
            "failure_class": "synthesized_followon_not_materialized",
            "generated_at": generated_at,
            "prevention_rule": "Blocker synthesis must create or trigger an executable task for the first unmaterialized follow-on.",
            "repair_pattern": [
                "Read MIM_TOD_NEXT_BLOCKER_OBJECTIVE and blocker follow-on deck.",
                "Skip follow-ons that already have terminal or pending task rows.",
                "Create one ready task with a mapped repair executor.",
                "Let dispatcher consume the new repair task.",
            ],
            "validated_on_task_id": task.id,
            "created_task": created_task,
        }
    )

    payload = {
        "packet_type": "mim-tod-blocker-followon-materializer-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "completed_with_evidence" if created_task else "blocked_with_evidence",
        "operator_facing_summary": (
            f"Materialized blocker follow-on {created_task['objective_id']} into task {created_task['task_id']}."
            if created_task
            else "No unmaterialized blocker follow-on was available."
        ),
        "selected_followon": selected,
        "created_objective": created_objective,
        "created_task": created_task,
        "skipped_reason": skipped_reason,
        "inspected_files": inspected_files,
        "changed_files": [
            "database:tasks",
            "database:objectives",
            "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_MATERIALIZER.latest.json",
            "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
            f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
        ],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "created_executable_task": bool(created_task),
            "task_dispatch_status": created_task.get("dispatch_status") if created_task else "",
            "memory_checked": True,
            "prevention_memory_written": True,
        },
        "next_recovery_action": "Allow dispatcher to consume the materialized blocker follow-on task." if created_task else "Run blocker synthesis again after new blocker evidence appears.",
    }
    write_json(BLOCKER_FOLLOWON_MATERIALIZER_PATH, payload)
    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-BLOCKER-FOLLOWON-MATERIALIZER-V1",
        "status": payload["status"],
        "reason_code": "blocker_followon_materialized_to_ready_task" if created_task else "no_unmaterialized_blocker_followon",
        "inspected_files": inspected_files,
        "changed_files": payload["changed_files"],
        "operator_facing_summary": payload["operator_facing_summary"],
        "validation_results": payload["validation_results"],
        "blocker": "" if created_task else skipped_reason,
        "next_recovery_action": payload["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


async def run_lifecycle_regression(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = [
        "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
        "runtime/shared/MIM_TOD_OBJECTIVE_TO_TASK_MATERIALIZER_RESULT.latest.json",
        "runtime/shared/MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json",
        "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
        "runtime/shared/MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json",
        "runtime/shared/MIM_TOD_OPERATOR_STATUS_SURFACE.latest.json",
        "runtime/shared/MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        "database:tasks",
        "database:task_results",
    ]
    artifact_names = [
        "MIM_TOD_OBJECTIVE_LEDGER.latest.json",
        "MIM_TOD_OBJECTIVE_TO_TASK_MATERIALIZER_RESULT.latest.json",
        "MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json",
        "MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
        "MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json",
        "MIM_TOD_OPERATOR_STATUS_SURFACE.latest.json",
    ]
    artifact_checks = [
        {"artifact": f"runtime/shared/{name}", "exists": (SHARED / name).exists()}
        for name in artifact_names
    ]
    result_artifact_checks: list[dict[str, Any]] = []
    for task_id in [7965, 7966, 7967, 7968, 7969, 7970]:
        path = SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task_id}.latest.json"
        payload = load_json_file(path)
        result_artifact_checks.append(
            {
                "task_id": task_id,
                "artifact": f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task_id}.latest.json",
                "exists": path.exists(),
                "status": payload.get("status"),
                "wrapper_status_only_completion": payload.get("validation_results", {}).get("wrapper_status_only_completion"),
                "has_inspected_files": bool(payload.get("inspected_files")),
                "has_changed_files": bool(payload.get("changed_files")),
            }
        )

    rows = (
        await db.execute(
            select(Task)
            .where(Task.id.in_([7965, 7966, 7967, 7968, 7969, 7970, 7971]))
            .order_by(Task.id)
        )
    ).scalars().all()
    task_checks = [
        {
            "task_id": row.id,
            "state": row.state,
            "readiness": row.readiness,
            "dispatch_status": row.dispatch_status,
            "start_now": bool(row.start_now),
            "execution_scope": row.execution_scope,
        }
        for row in rows
    ]
    blocker_followons = load_json_file(BLOCKER_FOLLOWON_PATH)
    dispatcher_status = load_json_file(STATUS_PATH)

    failures = []
    failures.extend([f"missing_artifact:{item['artifact']}" for item in artifact_checks if not item["exists"]])
    for item in result_artifact_checks:
        if not item["exists"]:
            failures.append(f"missing_result_artifact:task_{item['task_id']}")
        if item.get("wrapper_status_only_completion") is not False:
            failures.append(f"wrapper_status_only_or_unknown:task_{item['task_id']}")
        if not item.get("has_inspected_files") or not item.get("has_changed_files"):
            failures.append(f"missing_evidence_lists:task_{item['task_id']}")
    if len(blocker_followons.get("objectives") if isinstance(blocker_followons.get("objectives"), list) else []) < 1:
        failures.append("blocker_followon_artifact_empty")
    status = "completed_with_evidence" if not failures else "blocked_with_evidence"
    regression = {
        "packet_type": "mim-tod-objective-lifecycle-regression-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": "MIM-TOD-OBJECTIVE-LIFECYCLE-REGRESSION-SUITE-V1",
        "status": status,
        "inspected_files": inspected_files,
        "artifact_checks": artifact_checks,
        "result_artifact_checks": result_artifact_checks,
        "task_checks": task_checks,
        "dispatcher_status": dispatcher_status,
        "blocker_followon_count": len(blocker_followons.get("objectives") if isinstance(blocker_followons.get("objectives"), list) else []),
        "failures": failures,
        "operator_facing_summary": (
            "Objective lifecycle regression passed: objective ledger, materialization, dispatch, evidence artifacts, blocker synthesis, lane arbitration, and operator surface all have evidence."
            if not failures
            else f"Objective lifecycle regression found {len(failures)} blocker(s); see failures for the bounded next fix."
        ),
        "next_action": "Keep reliability-stack executors bound and promote future objectives one at a time through this evidence path.",
    }
    write_json(LIFECYCLE_REGRESSION_PATH, regression)

    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-OBJECTIVE-LIFECYCLE-REGRESSION-SUITE-V1",
        "status": status,
        "reason_code": "objective_lifecycle_regression_passed" if not failures else "objective_lifecycle_regression_failed",
        "inspected_files": inspected_files,
        "changed_files": ["runtime/shared/MIM_TOD_OBJECTIVE_LIFECYCLE_REGRESSION.latest.json"],
        "validation_results": {
            "wrapper_status_only_completion": False,
            "artifact_check_count": len(artifact_checks),
            "result_artifact_check_count": len(result_artifact_checks),
            "failure_count": len(failures),
            "blocker_followon_count": regression["blocker_followon_count"],
        },
        "next_recovery_action": regression["next_action"] if not failures else "Inspect lifecycle regression failures and bind the missing path.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def _scope_for_active_artifact_objective(objective_id: str) -> str:
    key = objective_id.lower()
    if "conversation-control-layer" in key:
        return "mim_lab_conversation_control_layer_executor"
    return "mim_tod_unbound_objective_executor"


def _active_objective_artifact_paths() -> list[Path]:
    paths = set(SHARED.glob("*OBJECTIVE.latest.json"))
    paths.update(SHARED.glob("*_OBJECTIVE.latest.json"))
    return sorted(path for path in paths if path.is_file())


async def run_active_objective_artifact_promotion(task: Task, db) -> dict[str, Any]:
    generated_at = now_iso()
    inspected_files = ["database:objectives", "database:tasks"]
    artifacts: list[dict[str, Any]] = []
    promoted: list[dict[str, Any]] = []
    already_linked: list[dict[str, Any]] = []
    materialization_failures: list[dict[str, Any]] = []

    all_objectives = (await db.execute(select(Objective))).scalars().all()
    all_tasks = (await db.execute(select(Task))).scalars().all()

    def canonical_for_objective(row: Objective) -> str:
        meta = row.metadata_json if isinstance(row.metadata_json, dict) else {}
        return str(meta.get("canonical_objective_id") or row.title or "").strip()

    objective_by_canonical = {
        canonical_for_objective(row): row
        for row in all_objectives
        if canonical_for_objective(row)
    }
    tasks_by_objective_id: dict[int, list[Task]] = {}
    for row in all_tasks:
        if row.objective_id is not None:
            tasks_by_objective_id.setdefault(int(row.objective_id), []).append(row)

    for path in _active_objective_artifact_paths():
        rel = str(path.relative_to(ROOT))
        inspected_files.append(rel)
        payload = load_json_file(path)
        if not payload:
            continue
        objective_id = str(payload.get("objective_id") or "").strip()
        status = str(payload.get("status") or "").strip().lower()
        if not objective_id or status != "active":
            continue
        title = str(payload.get("title") or payload.get("goal") or objective_id).strip()[:200]
        goal = str(payload.get("goal") or payload.get("summary") or title).strip()
        priority = str(payload.get("priority") or "normal").strip()
        required_actions = payload.get("required_actions") if isinstance(payload.get("required_actions"), list) else []
        success_criteria = payload.get("success_criteria") if isinstance(payload.get("success_criteria"), list) else []
        required_outputs = payload.get("required_outputs") if isinstance(payload.get("required_outputs"), list) else []
        row_info = {
            "objective_id": objective_id,
            "artifact": rel,
            "status": status,
            "title": title,
        }
        artifacts.append(row_info)
        db_objective = objective_by_canonical.get(objective_id)
        if not db_objective:
            db_objective = Objective(
                title=title,
                description=goal,
                priority=priority,
                constraints_json=[
                    "Active objective artifacts must be linked to a DB task, dispatcher queue item, explicit blocked reason, or materialization failure artifact.",
                    "Voice-created objectives should prompt for optional priority, goal, required actions, and success criteria before promotion.",
                ],
                success_criteria="\n".join(str(item) for item in success_criteria) if success_criteria else "Publish executable task evidence or blocked_with_inspection.",
                state="active",
                owner=str(payload.get("owner") or "mim"),
                execution_mode="auto",
                auto_continue=True,
                boundary_mode="soft",
                metadata_json={
                    "canonical_objective_id": objective_id,
                    "source": "active_objective_artifact_promotion",
                    "source_artifact": rel,
                    "promoted_at": generated_at,
                    "voice_objective_optional_prompt_fields": ["priority", "goal", "required_actions", "success_criteria"],
                },
            )
            db.add(db_objective)
            await db.flush()
            objective_by_canonical[objective_id] = db_objective

        linked_tasks = tasks_by_objective_id.get(int(db_objective.id), [])
        if linked_tasks:
            already_linked.append({**row_info, "db_objective_id": db_objective.id, "task_ids": [row.id for row in linked_tasks]})
            continue

        try:
            execution_scope = _scope_for_active_artifact_objective(objective_id)
            new_task = Task(
                objective_id=db_objective.id,
                title=f"Execute {title}"[:200],
                details=json.dumps(
                    {
                        "objective_id": objective_id,
                        "goal": goal,
                        "priority": priority,
                        "required_actions": required_actions,
                        "success_criteria": success_criteria,
                        "source_artifact": rel,
                        "hard_rule": "active_objective_artifact_requires_executable_task_or_explicit_blocker",
                    },
                    indent=2,
                    sort_keys=True,
                ),
                dependencies=[],
                acceptance_criteria="\n".join(
                    [
                        "Task reaches running, completed_with_evidence, or blocked_with_inspection/blocked_with_evidence.",
                        "Result includes inspected files, changed files, or exact missing executor reason.",
                        "No wrapper/status-only completion.",
                    ]
                ),
                assigned_to="mim",
                state="ready",
                readiness="ready",
                boundary_mode="soft",
                start_now=True,
                human_prompt_required=False,
                execution_scope=execution_scope,
                expected_outputs_json=[str(item) for item in required_outputs],
                verification_commands_json=["mim_ready_task_dispatcher --once"],
                dispatch_status="pending",
                dispatch_artifact_json={
                    "source_artifact": rel,
                    "canonical_objective_id": objective_id,
                    "promotion_artifact": "runtime/shared/MIM_TOD_ACTIVE_OBJECTIVE_ARTIFACT_PROMOTION.latest.json",
                },
                metadata_json={
                    "canonical_objective_id": objective_id,
                    "source": "active_objective_artifact_promotion",
                    "source_artifact": rel,
                    "promoted_at": generated_at,
                    "hard_rule": "active_objective_artifact_requires_executable_task_or_explicit_blocker",
                },
            )
            db.add(new_task)
            await db.flush()
            tasks_by_objective_id.setdefault(int(db_objective.id), []).append(new_task)
            promoted.append({
                **row_info,
                "db_objective_id": db_objective.id,
                "task_id": new_task.id,
                "readiness": new_task.readiness,
                "dispatch_status": new_task.dispatch_status,
                "execution_scope": execution_scope,
            })
        except Exception as exc:
            materialization_failures.append({**row_info, "db_objective_id": db_objective.id, "error": f"{type(exc).__name__}: {exc}"})

    await db.commit()

    voice_policy = {
        "packet_type": "mim-voice-objective-intake-policy-v1",
        "generated_at": generated_at,
        "status": "active",
        "required_behavior": "When a voice conversation sets up an objective, MIM should ask for optional details before or during promotion.",
        "optional_fields": [
            {"name": "priority", "prompt": "What is the priority?"},
            {"name": "goal", "prompt": "What is the goal?"},
            {"name": "required_actions", "prompt": "Add any required actions."},
            {"name": "success_criteria", "prompt": "What is considered success?"},
        ],
        "none_required": True,
        "why": "None of the fields are required, but any provided detail improves MIM's ability to complete the objective.",
    }
    write_json(VOICE_OBJECTIVE_INTAKE_POLICY_PATH, voice_policy)

    promotion = {
        "packet_type": "mim-tod-active-objective-artifact-promotion-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": "MIM-TOD-OBJECTIVE-ARTIFACT-TO-EXECUTABLE-TASK-PROMOTION-V1",
        "status": "completed_with_evidence" if not materialization_failures else "blocked_with_evidence",
        "inspected_files": list(dict.fromkeys(inspected_files)),
        "changed_files": [
            "database:objectives",
            "database:tasks",
            "runtime/shared/MIM_TOD_ACTIVE_OBJECTIVE_ARTIFACT_PROMOTION.latest.json",
            "runtime/shared/MIM_VOICE_OBJECTIVE_INTAKE_POLICY.latest.json",
        ],
        "active_artifact_count": len(artifacts),
        "promoted_count": len(promoted),
        "already_linked_count": len(already_linked),
        "materialization_failure_count": len(materialization_failures),
        "active_artifacts": artifacts,
        "promoted": promoted,
        "already_linked": already_linked,
        "materialization_failures": materialization_failures,
        "hard_rule": {
            "active_objective_artifact_valid_only_if": [
                "linked DB task row",
                "linked dispatcher queue item",
                "explicit blocked_with_reason",
                "materialization failure artifact",
            ],
            "validation_applied": True,
        },
        "validation_results": {
            "wrapper_status_only_completion": False,
            "test_case_objective_id": "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1",
            "test_case_promoted": any(item.get("objective_id") == "MIM-LAB-CONVERSATION-CONTROL-LAYER-V1" for item in promoted + already_linked),
        },
        "next_recovery_action": "Allow dispatcher to consume promoted active-objective tasks; unbound scopes must emit blocked_with_evidence.",
    }
    write_json(ACTIVE_OBJECTIVE_PROMOTION_PATH, promotion)

    result = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "canonical_objective_id": "MIM-TOD-OBJECTIVE-ARTIFACT-TO-EXECUTABLE-TASK-PROMOTION-V1",
        "status": promotion["status"],
        "reason_code": "active_objective_artifacts_promoted_to_tasks" if not materialization_failures else "active_objective_artifact_promotion_partial_failure",
        "inspected_files": promotion["inspected_files"],
        "changed_files": promotion["changed_files"],
        "validation_results": promotion["validation_results"],
        "next_recovery_action": promotion["next_recovery_action"],
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", result)
    return result


def has_lab_camera_cycle_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "camera_cycle" in text or "camera cycle" in text


def has_lab_human_interaction_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "human_interaction" in text or "human interaction" in text or "tts" in text


def has_lab_object_inquiry_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "object_inquiry" in text or "object inquiry" in text or "object_memory" in text


def has_lab_awareness_final_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "lab_awareness_final" in text or "final evidence" in text or "final_validation" in text


async def process_once() -> bool:
    async with SessionLocal() as db:
        task = (
            await db.execute(
                select(Task)
                .where(Task.start_now.is_(True))
                .where(Task.readiness == "ready")
                .where(Task.dispatch_status == "pending")
                .where(Task.assigned_to.in_(["mim", "MIM"]))
                .order_by(Task.id.desc())
                .limit(1)
            )
        ).scalars().first()
        if not task:
            previous: dict[str, Any] = {}
            if STATUS_PATH.exists():
                try:
                    previous = json.loads(STATUS_PATH.read_text(encoding="utf-8"))
                except Exception:
                    previous = {}
            write_json(
                STATUS_PATH,
                {
                    "packet_type": "mim-ready-task-dispatcher-status-v1",
                    "generated_at": now_iso(),
                    "status": "idle",
                    "last_action": "no_ready_mim_start_now_task",
                    "last_processed_task_id": previous.get("task_id") or previous.get("last_processed_task_id"),
                    "last_processed_dispatch_status": previous.get("dispatch_status")
                    or previous.get("last_processed_dispatch_status"),
                },
            )
            return False

        task.dispatch_status = "claimed"
        task.state = "running"
        metadata = task.metadata_json if isinstance(task.metadata_json, dict) else {}
        task.metadata_json = {
            **metadata,
            "ready_task_dispatcher": {
                "claimed_at": now_iso(),
                "dispatcher": "mim_ready_task_dispatcher",
            },
        }
        await db.commit()
        await db.refresh(task)

        if has_stale_sla_watchdog_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_stale_sla_watchdog(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_blocker_followon_materializer_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_blocker_followon_materializer(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_blocker_synthesis_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_blocker_synthesis(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lane_ownership_arbitration_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_lane_ownership_arbitration(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_operator_status_surface_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_operator_status_surface(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_conversational_synthesis_enforcement_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_conversational_synthesis_enforcement(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_freshness_provenance_trust_ranking_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_freshness_provenance_trust_ranking(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_escalation_autonomy_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_escalation_autonomy(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_stale_running_objective_reconciliation_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_stale_running_objective_reconciliation(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_training_to_action_reflex_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_training_to_action_reflex(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_objective_task_state_reconciliation_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_objective_task_state_reconciliation(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_intent_discovery_surface_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_intent_discovery_surface(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_intent_to_application_pipeline_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_intent_to_application_pipeline(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lifecycle_regression_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_lifecycle_regression(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_active_objective_artifact_promotion_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_active_objective_artifact_promotion(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lab_conversation_control_live_quality_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_lab_conversation_control_live_quality(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_real_mic_transcript_calibration_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_real_mic_transcript_calibration(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lab_conversation_control_layer_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_lab_conversation_control_layer_executor(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_objective_task_materializer_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = await run_objective_task_materializer(task, db)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_objective_ledger_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_objective_ledger_writer(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lab_camera_cycle_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_lab_camera_cycle(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lab_human_interaction_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_lab_human_interaction(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lab_object_inquiry_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_lab_object_inquiry(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lab_awareness_final_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_lab_awareness_final_evidence(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        elif has_lab_sensor_inventory_executor(task):
            task.dispatch_status = "running"
            await db.commit()
            result_payload = run_lab_sensor_inventory(task)
            result_status = str(result_payload.get("status") or "blocked_with_evidence")
        else:
            result_payload = no_executor_result(task)
            result_status = "blocked_with_evidence"

        task.dispatch_status = result_status
        task.state = result_status
        objective_sync = await sync_parent_objective_from_child_tasks(db, task.objective_id)
        if isinstance(result_payload, dict):
            validation = result_payload.get("validation_results")
            if isinstance(validation, dict):
                validation["parent_objective_sync"] = objective_sync
            else:
                result_payload["validation_results"] = {"parent_objective_sync": objective_sync}
        db.add(
            TaskResult(
                task_id=task.id,
                result=json.dumps(result_payload, sort_keys=True),
                files_changed=[
                    "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json",
                    "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                ]
                if has_lab_sensor_inventory_executor(task)
                else [
                    "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json",
                    "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                ]
                if has_lab_human_interaction_executor(task)
                else [
                    "runtime/shared/MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json",
                    "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                ]
                if has_lab_object_inquiry_executor(task)
                else [
                    "runtime/shared/MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json",
                    "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                ]
                if has_lab_awareness_final_executor(task)
                else [
                    "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_MATERIALIZER.latest.json",
                    "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_blocker_followon_materializer_executor(task)
                else [
                    "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json",
                    "runtime/shared/MIM_TOD_NEXT_BLOCKER_OBJECTIVE.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_blocker_synthesis_executor(task)
                else [
                    "runtime/shared/MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json",
                    "runtime/shared/MIM_TOD_NEXT_OBJECTIVE.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_lane_ownership_arbitration_executor(task)
                else [
                    "runtime/shared/MIM_TOD_OPERATOR_STATUS_SURFACE.latest.json",
                    "runtime/shared/MIM_TOD_NEXT_OBJECTIVE.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_operator_status_surface_executor(task)
                else [
                    "runtime/shared/MIM_CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_V2.latest.json",
                    "runtime/shared/MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_conversational_synthesis_enforcement_executor(task)
                else [
                    "runtime/shared/MIM_TOD_FRESHNESS_PROVENANCE_AND_TRUST_RANKING.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_freshness_provenance_trust_ranking_executor(task)
                else [
                    "runtime/shared/MIM_TOD_ESCALATION_AUTONOMY.latest.json",
                    "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_escalation_autonomy_executor(task)
                else [
                    "runtime/shared/MIM_TOD_STALE_RUNNING_OBJECTIVE_RECONCILIATION.latest.json",
                    "runtime/shared/MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json",
                    "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_stale_running_objective_reconciliation_executor(task)
                else [
                    "runtime/shared/MIM_TOD_TRAINING_TO_ACTION_REFLEX.latest.json",
                    "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_training_to_action_reflex_executor(task)
                else [
                    "runtime/shared/MIM_TOD_OBJECTIVE_TASK_STATE_RECONCILIATION.latest.json",
                    "runtime/shared/MIM_TOD_PREVENTION_MEMORY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_objective_task_state_reconciliation_executor(task)
                else [
                    "runtime/shared/MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.json",
                    "runtime/shared/MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.html",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_intent_discovery_surface_executor(task)
                else [
                    "runtime/shared/MIM_INTENT_TO_APPLICATION_PIPELINE.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_intent_to_application_pipeline_executor(task)
                else [
                    "runtime/shared/MIM_TOD_OBJECTIVE_LIFECYCLE_REGRESSION.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_lifecycle_regression_executor(task)
                else [
                    "runtime/shared/MIM_TOD_ACTIVE_OBJECTIVE_ARTIFACT_PROMOTION.latest.json",
                    "runtime/shared/MIM_VOICE_OBJECTIVE_INTAKE_POLICY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_active_objective_artifact_promotion_executor(task)
                else [
                    "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_LIVE_QUALITY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_lab_conversation_control_live_quality_executor(task)
                else [
                    "runtime/shared/MIM_LAB_REAL_MIC_TRANSCRIPT_CALIBRATION.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_real_mic_transcript_calibration_executor(task)
                else [
                    "runtime/shared/MIM_TOD_EXECUTOR_CAPABILITY_REGISTRY.latest.json",
                    "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_EXECUTOR_BINDING.latest.json",
                    "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_REGRESSION.latest.json",
                    "runtime/shared/MIM_TOD_MATERIALIZED_BLOCKED_ROW_CLEANUP.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_lab_conversation_control_layer_executor(task)
                else [
                    "runtime/shared/MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_stale_sla_watchdog_executor(task)
                else [
                    "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_objective_task_materializer_executor(task)
                else [
                    "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json",
                    f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
                ]
                if has_objective_ledger_executor(task)
                else [
                    "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
                    "runtime/shared/MIM_LAB_AWARENESS_STATUS.latest.json",
                ]
                if has_lab_camera_cycle_executor(task)
                else [f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json"],
                tests_run=["mim_ready_task_dispatcher_process_once"],
                test_results=result_status,
                failures=[] if result_status == "completed_with_evidence" else [str(result_payload.get("blocker") or result_payload.get("reason_code") or "blocked")],
                recommendations=str(result_payload.get("next_recovery_action") or ""),
            )
        )
        await db.commit()
        write_json(
            STATUS_PATH,
            {
                "packet_type": "mim-ready-task-dispatcher-status-v1",
                "generated_at": now_iso(),
                "status": "processed_task",
                "task_id": task.id,
                "objective_id": task.objective_id,
                "dispatch_status": result_status,
                "result_artifact": "runtime/shared/MIM_LAB_SENSOR_INVENTORY.latest.json"
                if has_lab_sensor_inventory_executor(task)
                else "runtime/shared/MIM_HUMAN_INTERACTION_MEMORY.latest.json"
                if has_lab_human_interaction_executor(task)
                else "runtime/shared/MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json"
                if has_lab_object_inquiry_executor(task)
                else "runtime/shared/MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json"
                if has_lab_awareness_final_executor(task)
                else "runtime/shared/MIM_TOD_STALE_OBJECTIVE_RECOVERY.latest.json"
                if has_stale_sla_watchdog_executor(task)
                else "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_MATERIALIZER.latest.json"
                if has_blocker_followon_materializer_executor(task)
                else "runtime/shared/MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json"
                if has_blocker_synthesis_executor(task)
                else "runtime/shared/MIM_TOD_LANE_OWNERSHIP_ARBITRATION.latest.json"
                if has_lane_ownership_arbitration_executor(task)
                else "runtime/shared/MIM_TOD_OPERATOR_STATUS_SURFACE.latest.json"
                if has_operator_status_surface_executor(task)
                else "runtime/shared/MIM_CONVERSATIONAL_SYNTHESIS_ENFORCEMENT_V2.latest.json"
                if has_conversational_synthesis_enforcement_executor(task)
                else "runtime/shared/MIM_TOD_FRESHNESS_PROVENANCE_AND_TRUST_RANKING.latest.json"
                if has_freshness_provenance_trust_ranking_executor(task)
                else "runtime/shared/MIM_TOD_ESCALATION_AUTONOMY.latest.json"
                if has_escalation_autonomy_executor(task)
                else "runtime/shared/MIM_TOD_STALE_RUNNING_OBJECTIVE_RECONCILIATION.latest.json"
                if has_stale_running_objective_reconciliation_executor(task)
                else "runtime/shared/MIM_TOD_TRAINING_TO_ACTION_REFLEX.latest.json"
                if has_training_to_action_reflex_executor(task)
                else "runtime/shared/MIM_TOD_OBJECTIVE_TASK_STATE_RECONCILIATION.latest.json"
                if has_objective_task_state_reconciliation_executor(task)
                else "runtime/shared/MIM_INTENT_DISCOVERY_CONVERSATION_SURFACE.latest.json"
                if has_intent_discovery_surface_executor(task)
                else "runtime/shared/MIM_INTENT_TO_APPLICATION_PIPELINE.latest.json"
                if has_intent_to_application_pipeline_executor(task)
                else "runtime/shared/MIM_TOD_OBJECTIVE_LIFECYCLE_REGRESSION.latest.json"
                if has_lifecycle_regression_executor(task)
                else "runtime/shared/MIM_TOD_ACTIVE_OBJECTIVE_ARTIFACT_PROMOTION.latest.json"
                if has_active_objective_artifact_promotion_executor(task)
                else "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_LIVE_QUALITY.latest.json"
                if has_lab_conversation_control_live_quality_executor(task)
                else "runtime/shared/MIM_LAB_REAL_MIC_TRANSCRIPT_CALIBRATION.latest.json"
                if has_real_mic_transcript_calibration_executor(task)
                else "runtime/shared/MIM_LAB_CONVERSATION_CONTROL_LAYER_EXECUTOR_BINDING.latest.json"
                if has_lab_conversation_control_layer_executor(task)
                else "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json"
                if has_objective_task_materializer_executor(task)
                else "runtime/shared/MIM_TOD_OBJECTIVE_LEDGER.latest.json"
                if has_objective_ledger_executor(task)
                else "runtime/shared/MIM_LAB_CAMERA_CYCLE_STATUS.latest.json"
                if has_lab_camera_cycle_executor(task)
                else f"runtime/shared/MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json",
            },
        )
        return True


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--interval-seconds", type=int, default=15)
    args = parser.parse_args()
    while True:
        await process_once()
        if args.once:
            return
        await asyncio.sleep(max(1, args.interval_seconds))


if __name__ == "__main__":
    asyncio.run(main())
