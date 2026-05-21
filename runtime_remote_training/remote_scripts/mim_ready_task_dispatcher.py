#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import subprocess
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
    payload: dict[str, Any] = {
        "device_id": "arm-camera-bridge",
        "source_type": "arm_camera",
        "exists": bool(existing),
        "openable": False,
        "last_frame_or_sample_time": None,
        "probe_method": "bridge artifact inspection; no arm movement",
        "inspected_paths": inspected,
        "error": "no_current_arm_camera_bridge_probe_bound",
    }
    if existing:
        payload["bridge_artifacts_present"] = [str(path.relative_to(ROOT)) for path in existing]
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

        if has_lab_sensor_inventory_executor(task):
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
