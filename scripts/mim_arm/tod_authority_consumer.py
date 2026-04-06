import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a stable mim_arm-side TOD authority summary.")
    parser.add_argument("--input", required=True, help="Path to TOD_INTEGRATION_STATUS.latest.json")
    parser.add_argument("--output", required=True, help="Path to write TOD_AUTHORITY_SUMMARY.latest.json")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    payload = load_json(input_path)

    objective_alignment = payload.get("objective_alignment") or {}
    publish = payload.get("tod_status_publish") or {}
    mim_status = payload.get("mim_status") or {}
    live_task_request = payload.get("live_task_request") or {}

    summary = {
        "generated_at": utc_now(),
        "source": "mim-arm-tod-authority-summary-v1",
        "input_path": str(input_path),
        "input_generated_at": payload.get("generated_at", ""),
        "input_sha256": sha256_text(json.dumps(payload, sort_keys=True, separators=(",", ":"))),
        "authority": {
            "status": publish.get("status", "unknown"),
            "enabled": bool(publish.get("enabled", False)),
            "uploaded_at": publish.get("uploaded_at", ""),
            "compatible": bool(payload.get("compatible", False)),
            "compatibility_reason": payload.get("compatibility_reason", "unknown"),
        },
        "objective": {
            "tod_current": objective_alignment.get("tod_current_objective", ""),
            "mim_current": objective_alignment.get("mim_objective_active", ""),
            "aligned": bool(objective_alignment.get("aligned", False)),
            "alignment_status": objective_alignment.get("status", "unknown"),
            "alignment_source": objective_alignment.get("mim_objective_source", "unknown"),
            "live_request_id": live_task_request.get("request_id", ""),
        },
        "mim_status": {
            "available": bool(mim_status.get("available", False)),
            "phase": mim_status.get("phase", "unknown"),
            "is_stale": bool(mim_status.get("is_stale", True)),
            "generated_at": mim_status.get("generated_at", ""),
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()