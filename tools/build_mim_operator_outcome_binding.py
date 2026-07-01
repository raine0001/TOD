"""Bind MIM operator-impact replies to expected outcome evidence.

This does not claim outcome success. It creates the audit layer that tracks
whether each scored MIM recommendation has an evidence expectation and whether
that evidence is currently observable from local training artifacts.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import re
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"
LIVE_10_PATH = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
OUTPUT_PATH = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json"
OUTPUT_MD_PATH = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.md"

ARTIFACT_RE = re.compile(r"\b[A-Z0-9_./\\-]+\.latest\.(?:json|md)\b")


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return value if isinstance(value, dict) else {}


def _resolve_artifact_path(text_path: str) -> Path:
    normalized = text_path.replace("\\", "/")
    if normalized.startswith("runtime_remote_training/"):
        return ROOT / normalized
    if normalized.startswith("runtime/shared/"):
        return ROOT / normalized
    return TRAINING_ROOT / normalized


def _extract_artifacts(reply: str) -> list[str]:
    seen: set[str] = set()
    artifacts: list[str] = []
    for match in ARTIFACT_RE.findall(reply):
        normalized = match.strip().replace("\\", "/")
        if normalized not in seen:
            seen.add(normalized)
            artifacts.append(normalized)
    return artifacts


def _has_expected_evidence(reply: str) -> bool:
    return bool(re.search(r"\b(expected evidence|evidence:|artifact|validation|proof|record|scorecard)\b", reply, re.I))


def build_binding() -> dict[str, Any]:
    live = _load_json(LIVE_10_PATH)
    cases = live.get("scored_cases") if isinstance(live.get("scored_cases"), list) else []
    records: list[dict[str, Any]] = []
    observed_count = 0
    expected_count = 0
    pending_count = 0

    for case in cases:
        if not isinstance(case, dict):
            continue
        reply = str(case.get("reply_excerpt") or "")
        artifacts = _extract_artifacts(reply)
        observed = []
        missing = []
        for artifact in artifacts:
            resolved = _resolve_artifact_path(artifact)
            if resolved.exists():
                observed.append({"artifact": artifact, "path": str(resolved), "exists": True})
            else:
                missing.append({"artifact": artifact, "path": str(resolved), "exists": False})
        expected = _has_expected_evidence(reply)
        if expected:
            expected_count += 1
        if observed:
            observed_count += 1
        if expected and not observed:
            pending_count += 1
        records.append(
            {
                "id": case.get("id"),
                "prompt": case.get("prompt"),
                "expected_evidence_stated": expected,
                "named_artifacts": artifacts,
                "observed_artifacts": observed,
                "missing_artifacts": missing,
                "outcome_status": "observed_artifact" if observed else ("pending_observation" if expected else "missing_expected_evidence"),
                "movement_status": "pending_project_successor_check",
                "dave_needed": "no",
            }
        )

    total = len(records)
    generated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return {
        "packet_type": "mim-operator-impact-outcome-binding-v1",
        "generated_at": generated_at,
        "source": str(LIVE_10_PATH),
        "status": "binding_active" if total else "no_samples",
        "sample_count": total,
        "expected_evidence_count": expected_count,
        "observed_artifact_count": observed_count,
        "pending_observation_count": pending_count,
        "records": records,
        "next_action": "Compare pending records to project/successor movement after the next active training cycle.",
    }


def write_outputs(payload: dict[str, Any]) -> None:
    OUTPUT_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    lines = [
        "# MIM Operator Impact Outcome Binding",
        "",
        f"Generated: {payload.get('generated_at')}",
        f"Status: {payload.get('status')}",
        f"Samples: {payload.get('sample_count')}",
        f"Expected evidence stated: {payload.get('expected_evidence_count')}",
        f"Observed artifact evidence: {payload.get('observed_artifact_count')}",
        f"Pending observation: {payload.get('pending_observation_count')}",
        "",
        f"Next action: {payload.get('next_action')}",
    ]
    OUTPUT_MD_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    payload = build_binding()
    write_outputs(payload)
    print(f"Wrote {OUTPUT_PATH}")
    print(f"Wrote {OUTPUT_MD_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
