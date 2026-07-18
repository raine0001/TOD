#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "runtime" / "shared"
EVIDENCE_HISTORY = ROOT / "docs" / "evidence-history"

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


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def nested_get(payload: dict[str, Any], *keys: str) -> Any:
    current: Any = payload
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def first_nonempty(*vals: Any) -> str:
    for val in vals:
        text = str(val or "").strip()
        if text:
            return text
    return ""


def _is_pending_capture(payload: dict[str, Any]) -> bool:
    status = str(payload.get("capture_status") or "").strip().lower()
    return status in {"", "pending", "pending_remote_capture", "todo"}


def _has_required_field_values(payload: dict[str, Any]) -> bool:
    for field in REQUIRED_FIELDS:
        value = payload.get(field)
        if value not in (None, ""):
            return True
    return False


def checkpoint_complete(payload: dict[str, Any]) -> bool:
    if not payload:
        return False
    if _is_pending_capture(payload):
        return False
    return _has_required_field_values(payload)


def build_a_checkpoint(request: dict[str, Any]) -> dict[str, Any]:
    meta = request.get("metadata_json") if isinstance(request.get("metadata_json"), dict) else {}
    out: dict[str, Any] = {}
    for field in REQUIRED_FIELDS:
        out[field] = request.get(field)
        if out[field] in (None, ""):
            out[field] = meta.get(field)
    return out


def build_package() -> dict[str, Any]:
    trace = read_json(SHARED / "TOD_REMOTE_PREACTIVE_ARBITRATION_FIELD_TRACE.latest.json")
    proof = read_json(SHARED / "TOD_REMOTE_PREACTIVE_GATE_LIVE_PROOF.latest.json")
    result = read_json(SHARED / "TOD_MIM_TASK_RESULT.latest.json")
    request = read_json(SHARED / "MIM_TOD_TASK_REQUEST.latest.json")

    local_a = build_a_checkpoint(request)

    validator_output = first_nonempty(
        nested_get(result, "validator", "output"),
        "",
    )

    package = {
        "generated_at": utc_now(),
        "objective_id": "TOD-REMOTE-PREACTIVE-ARBITRATION-FIELD-TRACE-V1",
        "status": "remote_capture_package_ready",
        "remote_owner": "TOD-3322",
        "remote_service": first_nonempty(trace.get("remote_service"), "mim-box-tod-packet-listener-v1"),
        "remote_entrypoint": first_nonempty(trace.get("remote_entrypoint"), "Start-TODMimPacketListener.ps1"),
        "required_fields": REQUIRED_FIELDS,
        "checkpoint_A_local_bridge_output": {
            "artifact": "runtime/shared/MIM_TOD_TASK_REQUEST.latest.json",
            "values": local_a,
        },
        "checkpoint_B_remote_staged_file": {
            "artifact_expected": first_nonempty(trace.get("staged_request_path"), "E:\\\\TOD\\\\tod\\\\out\\\\context-sync\\\\listener\\\\MIM_TOD_TASK_REQUEST.validator.<id>.json"),
            "capture_required": True,
            "capture_output_path": "runtime/shared/TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_b.staged_request.json",
        },
        "checkpoint_C_normalized_arbitration_object": {
            "artifact_expected": "normalized object immediately before pre-active gate validation in remote listener",
            "capture_required": True,
            "capture_output_path": "runtime/shared/TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_c.normalized_object.json",
        },
        "checkpoint_D_gate_input": {
            "artifact_expected": "exact gate input payload and rule evaluation context",
            "capture_required": True,
            "capture_output_path": "runtime/shared/TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_d.gate_input.json",
            "known_outcome": {
                "result_status": nested_get(proof, "single_run_evidence", "result_status") or result.get("result_status"),
                "result_reason_code": nested_get(proof, "single_run_evidence", "result_reason_code") or result.get("result_reason_code"),
                "listener_error": nested_get(proof, "single_run_evidence", "listener_error") or result.get("error"),
            },
        },
        "remote_capture_steps": [
            "1) On TOD-3322, locate active validator file for the target request_id/task_id and copy full JSON to checkpoint B output path.",
            "2) Instrument Start-TODMimPacketListener.ps1 to emit normalized pre-active object for the same request to checkpoint C output path.",
            "3) Emit exact pre-active gate input payload and evaluated rule names to checkpoint D output path.",
            "4) Copy all three checkpoint files back to runtime/shared in this repo.",
            "5) Run scripts/generate_remote_preactive_field_trace_package.py --merge-captures to produce an A/B/C/D diff artifact.",
        ],
        "capture_command_hint": "python3 scripts/generate_remote_preactive_field_trace_package.py --merge-captures",
        "validator_output_excerpt": validator_output[:1200],
    }

    return package


def merge_captures(base_package: dict[str, Any]) -> dict[str, Any]:
    b = read_json(SHARED / "TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_b.staged_request.json")
    c = read_json(SHARED / "TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_c.normalized_object.json")
    d = read_json(SHARED / "TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_d.gate_input.json")
    a = nested_get(base_package, "checkpoint_A_local_bridge_output", "values")
    if not isinstance(a, dict):
        a = {}

    checkpoint_completeness = {
        "B": checkpoint_complete(b),
        "C": checkpoint_complete(c),
        "D": checkpoint_complete(d),
    }
    all_complete = all(checkpoint_completeness.values())

    field_matrix: dict[str, Any] = {}
    field_first_divergence_checkpoint: dict[str, Any] = {}
    first_drift = ""

    for field in REQUIRED_FIELDS:
        av = a.get(field)
        bv = b.get(field)
        cv = c.get(field)
        dv = d.get(field)
        equal = av == bv == cv == dv

        first_divergence_checkpoint = "none"
        if bv != av:
            first_divergence_checkpoint = "B"
        elif cv != bv:
            first_divergence_checkpoint = "C"
        elif dv != cv:
            first_divergence_checkpoint = "D"

        if not equal and not first_drift:
            first_drift = field
        field_matrix[field] = {
            "A": av,
            "B": bv,
            "C": cv,
            "D": dv,
            "equal": equal,
        }
        field_first_divergence_checkpoint[field] = first_divergence_checkpoint

    merged = {
        "generated_at": utc_now(),
        "objective_id": "TOD-REMOTE-PREACTIVE-ARBITRATION-FIELD-TRACE-V1",
        "status": "abcd_field_diff_completed" if all_complete else "abcd_field_diff_incomplete",
        "required_fields": REQUIRED_FIELDS,
        "first_drift_field": (first_drift or "none") if all_complete else "insufficient_BCD_capture",
        "checkpoint_completeness": checkpoint_completeness,
        "field_first_divergence_checkpoint": field_first_divergence_checkpoint,
        "field_matrix": field_matrix,
        "checkpoints": {
            "A": "runtime/shared/MIM_TOD_TASK_REQUEST.latest.json",
            "B": "runtime/shared/TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_b.staged_request.json",
            "C": "runtime/shared/TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_c.normalized_object.json",
            "D": "runtime/shared/TOD_REMOTE_PREACTIVE_TRACE_CAPTURE.checkpoint_d.gate_input.json",
        },
    }
    return merged


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate and merge remote pre-active field trace capture package.")
    parser.add_argument("--merge-captures", action="store_true", help="Merge B/C/D capture files with local A checkpoint and emit field diff.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    package = build_package()

    package_path = SHARED / "TOD_REMOTE_PREACTIVE_TRACE_CAPTURE_PACKAGE.latest.json"
    write_json(package_path, package)

    if args.merge_captures:
        merged = merge_captures(package)
        merged_path = SHARED / "TOD_REMOTE_PREACTIVE_ARBITRATION_FIELD_TRACE_DIFF.latest.json"
        write_json(merged_path, merged)
        print(str(merged_path))

    print(str(package_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
