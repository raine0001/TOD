#!/usr/bin/env python3
"""Generate TOD borrowed-capability training priority artifacts."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.build_organizational_maintenance_scorecard import (  # noqa: E402
    borrowed_capability_ratio,
    parse_apprenticeship_registry,
)

TRAINING_ROOT = ROOT / "runtime_remote_training"
REGISTRY_PATH = ROOT / "docs" / "training" / "TOD_APPRENTICESHIP_REGISTRY.md"
OUTPUT_JSON = TRAINING_ROOT / "TOD_BORROWED_CAPABILITY_RETIREMENT_PLAN.latest.json"
OUTPUT_MD = TRAINING_ROOT / "TOD_BORROWED_CAPABILITY_RETIREMENT_PLAN.latest.md"


FAMILIES: list[dict[str, Any]] = [
    {
        "priority": 1,
        "family": "Read-Only Assessment And Authority Classification",
        "entry_ids": ["APP-TOD-034", "APP-TOD-033", "APP-TOD-032", "APP-TOD-036"],
        "why_now": "APP-TOD-034 already has an independent demo, so adjacent read-only/authority debt is the fastest responsible reduction target.",
        "proof_artifact": "runtime_remote_training/read_only_audit_artifacts/TOD_READ_ONLY_AUTHORITY_CLASSIFICATION_RETIREMENT_PROOF.latest.json",
    },
    {
        "priority": 2,
        "family": "Current-Code Bounded Packet Materialization",
        "entry_ids": ["APP-TOD-031", "APP-TOD-018", "APP-TOD-021", "APP-TOD-022", "APP-TOD-016"],
        "why_now": "This is the largest remaining independence blocker for implementation work.",
        "proof_artifact": "runtime_remote_training/tod_independent_resolution_attempts/TOD_CURRENT_CODE_PACKET_MATERIALIZATION_RETIREMENT_PROOF.latest.json",
    },
    {
        "priority": 3,
        "family": "Recovery That Produces Executable Retry Shape",
        "entry_ids": ["APP-TOD-011", "APP-TOD-023", "APP-TOD-004", "APP-TOD-020"],
        "why_now": "TOD can often name blockers but still needs to produce corrected executable attempts.",
        "proof_artifact": "runtime_remote_training/tod_result_artifacts/TOD_EXECUTABLE_RECOVERY_SHAPE_RETIREMENT_PROOF.latest.json",
    },
    {
        "priority": 4,
        "family": "Response Authority And MIM Cognition Boundary",
        "entry_ids": ["APP-TOD-001", "APP-TOD-006", "APP-TOD-007", "APP-TOD-010", "APP-TOD-024", "APP-TOD-027", "APP-TOD-028", "APP-TOD-029"],
        "why_now": "High impact, but safer after read-only classification and packet materialization improve.",
        "proof_artifact": "runtime_remote_training/read_only_audit_artifacts/TOD_RESPONSE_AUTHORITY_BOUNDARY_RETIREMENT_PROOF.latest.json",
    },
    {
        "priority": 5,
        "family": "Evidence-Derived Research And Product Answers",
        "entry_ids": ["APP-TOD-002", "APP-TOD-013", "APP-TOD-015", "APP-TOD-029"],
        "why_now": "Observatory and Enterprise require answers derived from evidence, not static text.",
        "proof_artifact": "runtime_remote_training/read_only_audit_artifacts/TOD_EVIDENCE_DERIVED_ANSWER_RETIREMENT_PROOF.latest.json",
    },
    {
        "priority": 6,
        "family": "MIM/TOD Coordination Contract And Status Truth",
        "entry_ids": ["APP-TOD-005", "APP-TOD-014", "APP-TOD-017", "APP-TOD-020", "APP-TOD-035"],
        "why_now": "Coordination truth affects every operator-facing page and every blocker loop.",
        "proof_artifact": "runtime_remote_training/tod_result_artifacts/TOD_COORDINATION_STATUS_TRUTH_RETIREMENT_PROOF.latest.json",
    },
    {
        "priority": 7,
        "family": "Cross-Service Live Verification And Deployment Pattern",
        "entry_ids": ["APP-TOD-009", "APP-TOD-025"],
        "why_now": "Deployment is important, but should follow stronger packet and recovery skills.",
        "proof_artifact": "runtime_remote_training/tod_result_artifacts/TOD_DEPLOYMENT_PATTERN_RETIREMENT_PROOF.latest.json",
    },
    {
        "priority": 8,
        "family": "AgentMIM Production Assimilation",
        "entry_ids": ["APP-TOD-019", "APP-TOD-026", "APP-TOD-030", "APP-TOD-012"],
        "why_now": "AgentMIM is outward-facing and should absorb recent Codex repairs after general execution skills improve.",
        "proof_artifact": "runtime_remote_training/tod_result_artifacts/TOD_AGENTMIM_ASSIMILATION_RETIREMENT_PROOF.latest.json",
    },
]


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def build_plan() -> dict[str, Any]:
    registry_text = REGISTRY_PATH.read_text(encoding="utf-8") if REGISTRY_PATH.exists() else ""
    entries = parse_apprenticeship_registry(registry_text)
    by_id: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        by_id.setdefault(str(entry["id"]), []).append(entry)
    duplicate_ids = {
        entry_id: matching_entries
        for entry_id, matching_entries in by_id.items()
        if len(matching_entries) > 1
    }
    ratio = borrowed_capability_ratio(entries)
    families: list[dict[str, Any]] = []
    for family in FAMILIES:
        family_entries = []
        for entry_id in family["entry_ids"]:
            family_entries.extend(by_id.get(entry_id, []))
        families.append(
            {
                **family,
                "entries": family_entries,
                "pass_gate": {
                    "unique_objective_id": True,
                    "inspected_evidence": True,
                    "changed_files_or_meaningful_artifact_write": True,
                    "validation_command": True,
                    "validation_result": True,
                    "rollback_note": True,
                    "prevention_lesson": True,
                    "no_wrapper_only_completion": True,
                    "classification": "independent|guided|scaffolded|borrowed",
                },
            }
        )
    return {
        "artifact_type": "tod_borrowed_capability_retirement_plan_v1",
        "generated_at": utc_now(),
        "objective_id": "TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1",
        "baseline_ratio": ratio,
        "registry_integrity": {
            "duplicate_ids": duplicate_ids,
            "duplicate_id_count": len(duplicate_ids),
            "status": "needs_cleanup" if duplicate_ids else "passed",
            "next_action": "Assign unique registry IDs before using per-entry retirement math."
            if duplicate_ids
            else "No duplicate registry IDs detected.",
        },
        "training_families": families,
        "twelve_hour_focus": [
            "Read-Only Assessment And Authority Classification",
            "Current-Code Bounded Packet Materialization",
            "Recovery That Produces Executable Retry Shape",
            "MIM/TOD Coordination Contract And Status Truth",
            "Response Authority And MIM Cognition Boundary as read-only audit only if time remains",
        ],
        "first_task": {
            "objective_id": "TOD-READONLY-AUTHORITY-CLASSIFICATION-RETIREMENT-PROOF-V1",
            "owner": "TOD",
            "acceptance": "TOD independently performs a fresh read-only authority classification without source-code mutation, publishes evidence, validates the artifact, and identifies which apprenticeship entries can advance.",
        },
    }


def write_outputs(plan: dict[str, Any]) -> None:
    TRAINING_ROOT.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# TOD Borrowed Capability Retirement Plan",
        "",
        f"Generated: {plan['generated_at']}",
        "",
        "## Baseline",
        "",
        f"- Borrowed: {plan['baseline_ratio']['current']['borrowed_percent']}%",
        f"- Independent: {plan['baseline_ratio']['current']['independent_percent']}%",
        f"- Entries: {plan['baseline_ratio']['current']['total_entries']}",
        f"- Registry duplicate IDs: {plan['registry_integrity']['duplicate_id_count']}",
        "",
        "## Training Families",
        "",
    ]
    for family in plan["training_families"]:
        lines.extend(
            [
                f"### {family['priority']}. {family['family']}",
                "",
                family["why_now"],
                "",
                "Entries:",
            ]
        )
        for entry in family["entries"]:
            lines.append(f"- `{entry['id']}` `{entry['progress']}` - {entry['name']}")
        lines.extend(["", f"Proof artifact: `{family['proof_artifact']}`", ""])
    lines.extend(["## First Task", "", plan["first_task"]["objective_id"], "", plan["first_task"]["acceptance"], ""])
    OUTPUT_MD.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    plan = build_plan()
    write_outputs(plan)
    print(f"wrote {OUTPUT_JSON.relative_to(ROOT)}")
    print(f"wrote {OUTPUT_MD.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
