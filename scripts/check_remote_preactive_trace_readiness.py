#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "runtime" / "shared"
MERGE_SCRIPT = ROOT / "scripts" / "generate_remote_preactive_field_trace_package.py"

REQUIRED_FIELDS = [
    "bounded_edit_mode",
    "target_file",
    "edit_mode",
    "anchor_or_old_text",
    "new_text_or_snippet",
    "validation_command",
    "closure_evidence",
    "prevention_lesson",
    "dave_needed",
    "objective_id",
    "task_id",
    "request_id",
    "correlation_id",
]

CHECKPOINTS = {
    "B": SHARED / "TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_b.staged_request.json",
    "C": SHARED / "TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_c.normalized_object.json",
    "D": SHARED / "TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_d.gate_input.json",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def has_required_values(payload: dict[str, Any]) -> bool:
    for field in REQUIRED_FIELDS:
        if payload.get(field) not in (None, ""):
            return True
    return False


def checkpoint_ready(payload: dict[str, Any]) -> tuple[bool, str]:
    status = str(payload.get("capture_status") or "").strip().lower()
    if status in {"", "pending", "pending_remote_capture", "todo"}:
        return False, "capture_status_pending"
    if not has_required_values(payload):
        return False, "required_fields_all_empty"
    return True, "ready"


def write_progress(payload: dict[str, Any]) -> None:
    path = SHARED / "TOD_REMOTE_PREACTIVE_ARBITRATION_FIELD_TRACE_PROGRESS.latest.json"
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def run_merge() -> tuple[bool, str]:
    cmd = [sys.executable, str(MERGE_SCRIPT), "--merge-captures"]
    proc = subprocess.run(cmd, cwd=ROOT, check=False, capture_output=True, text=True)
    merged_output = (proc.stdout or "").strip()
    if proc.returncode != 0:
        return False, (proc.stderr or merged_output or "merge_failed").strip()
    return True, merged_output


def main() -> int:
    report: dict[str, Any] = {
        "generated_at": utc_now(),
        "objective_id": "TOD-REMOTE-PREACTIVE-ARBITRATION-FIELD-TRACE-V1",
        "checkpoint_readiness": {},
        "all_ready": False,
        "merge_executed": False,
    }

    all_ready = True
    for label, path in CHECKPOINTS.items():
        payload = read_json(path)
        ready, reason = checkpoint_ready(payload)
        report["checkpoint_readiness"][label] = {
            "path": str(path.relative_to(ROOT)),
            "exists": path.exists(),
            "capture_status": payload.get("capture_status"),
            "ready": ready,
            "reason": reason,
        }
        if not ready:
            all_ready = False

    report["all_ready"] = all_ready

    if not all_ready:
        report["status"] = "waiting_for_remote_bcd_capture"
        report["next_action"] = "populate B/C/D capture files with real remote payloads then rerun this checker"
        write_progress(report)
        print(json.dumps(report, indent=2))
        return 2

    ok, output = run_merge()
    report["merge_executed"] = True
    report["merge_result"] = "ok" if ok else "failed"
    report["merge_output"] = output
    report["status"] = "merge_completed" if ok else "merge_failed"
    report["next_action"] = "inspect TOD_REMOTE_PREACTIVE_ARBITRATION_FIELD_TRACE_DIFF.latest.json for first-loss checkpoint"
    write_progress(report)
    print(json.dumps(report, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
