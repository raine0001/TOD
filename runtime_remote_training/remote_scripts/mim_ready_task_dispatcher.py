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
from core.models import Task, TaskResult


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
STATUS_PATH = SHARED / "MIM_READY_TASK_DISPATCHER_STATUS.latest.json"


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
    payload = {
        "packet_type": "mim-ready-task-dispatcher-result-v1",
        "generated_at": generated_at,
        "task_id": task.id,
        "objective_id": task.objective_id,
        "status": "blocked_with_evidence",
        "reason_code": "no_executor_bound",
        "inspected_queue": True,
        "inspected_dispatcher": True,
        "execution_scope": task.execution_scope,
        "assigned_to": task.assigned_to,
        "next_recovery_action": "Bind an executor for this execution_scope before marking the task complete.",
    }
    write_json(SHARED / f"MIM_READY_TASK_DISPATCHER_RESULT.task-{task.id}.latest.json", payload)
    return payload


def has_lab_sensor_inventory_executor(task: Task) -> bool:
    text = " ".join([task.execution_scope or "", task.title or "", task.details or ""]).lower()
    return "sensor_inventory" in text or "lab sensor" in text


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

        if has_lab_camera_cycle_executor(task):
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
