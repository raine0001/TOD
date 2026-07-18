#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = (
    ROOT
    / "runtime_remote_training"
    / "worktree_hygiene"
    / "TOD_WORKTREE_PATH_CLASSIFICATION_MATERIALIZER_V1.current.json"
)
DEFAULT_OUTPUT = (
    ROOT
    / "runtime_remote_training"
    / "worktree_hygiene"
    / "TOD_WORKTREE_CLEANUP_EXECUTION_V1.latest.json"
)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return payload


def _paths(entries: list[dict[str, Any]], *prefixes: str) -> list[str]:
    selected: list[str] = []
    for entry in entries:
        path = str(entry.get("path") or "")
        if any(path == prefix or path.startswith(prefix) for prefix in prefixes):
            selected.append(path)
    return selected


def _bucket(entries: list[dict[str, Any]], bucket: str) -> list[str]:
    return [str(entry["path"]) for entry in entries if entry.get("bucket") == bucket]


def build_execution_manifest(classification: dict[str, Any]) -> dict[str, Any]:
    entries = classification.get("paths")
    if not isinstance(entries, list):
        raise ValueError("Classification manifest must contain paths")

    normalized_entries = [
        entry
        for entry in entries
        if isinstance(entry, dict) and str(entry.get("path") or "").strip()
    ]
    buckets = Counter(str(entry.get("bucket") or "missing") for entry in normalized_entries)

    current_codex_slice = sorted(
        set(
            _paths(
                normalized_entries,
                "scripts/materialize_tod_worktree_path_classification.py",
                "scripts/materialize_tod_worktree_cleanup_execution.py",
                "tests/test_tod_worktree_path_classification_materializer.py",
                "tests/test_tod_worktree_cleanup_execution_materializer.py",
                "tmp_remote_mim/core/routers/observatory.py",
                "tmp_remote_mim/tests/test_observatory_routes.py",
                "runtime_remote_training/worktree_hygiene/TOD_WORKTREE_PATH_CLASSIFICATION_MATERIALIZER_V1.latest.json",
                "runtime_remote_training/worktree_hygiene/TOD_WORKTREE_PATH_CLASSIFICATION_MATERIALIZER_V1.current.json",
                "runtime_remote_training/worktree_hygiene/TOD_WORKTREE_CLEANUP_EXECUTION_V1.latest.json",
                "runtime_remote_training/read_only_audit_artifacts/MIM_ENTERPRISE_EXPERIENCE_V1_CURRENT_FLOW_AND_STARTED_OBJECTIVE.latest.json",
            )
        )
    )

    execution_slices = [
        {
            "slice_id": "commit_current_codex_reviewed_slice",
            "owner": "Codex validator now; TOD must assimilate",
            "action": "stage_exact_paths_only_after_validation",
            "risk": "medium",
            "paths": current_codex_slice,
            "validation": [
                "python tests/test_tod_worktree_path_classification_materializer.py",
                "python tests/test_tod_worktree_cleanup_execution_materializer.py",
                ".venv/Scripts/python.exe tmp_remote_mim/tests/test_observatory_routes.py",
                ".venv/Scripts/python.exe tmp_remote_mim/tests/test_enterprise_service.py",
                ".venv/Scripts/python.exe -m py_compile tmp_remote_mim/core/routers/observatory.py scripts/materialize_tod_worktree_path_classification.py scripts/materialize_tod_worktree_cleanup_execution.py",
            ],
            "completion_evidence": "one intentional commit containing only the listed paths",
        },
        {
            "slice_id": "tod_control_plane_review",
            "owner": "TOD",
            "action": "review_diff_validate_control_plane_then_commit_or_split",
            "risk": "high",
            "paths": sorted(
                _bucket(normalized_entries, "tod_control_plane_script")
                + _bucket(normalized_entries, "tod_control_plane_tool")
                + _bucket(normalized_entries, "tod_configuration_change")
            ),
            "validation": [
                "run focused PowerShell tests for touched TOD control-plane scripts",
                "prove no wrapper-only completion",
            ],
            "completion_evidence": "coherent TOD control-plane commit or precise blocker record",
        },
        {
            "slice_id": "remote_mim_product_patch_review",
            "owner": "MIM + TOD",
            "action": "split_into_reviewable_product_patch_with_tests_before_commit",
            "risk": "high",
            "paths": sorted(
                path
                for path in _bucket(normalized_entries, "remote_mim_product_patch")
                if path not in current_codex_slice
            ),
            "validation": [
                "run feature-specific tmp_remote_mim tests",
                "publish deployment or blocked evidence before staging",
            ],
            "completion_evidence": "one feature-scope MIM product commit per tested behavior",
        },
        {
            "slice_id": "training_and_capability_artifacts",
            "owner": "MIM + TOD",
            "action": "promote_only_evidence_backed_artifacts",
            "risk": "medium",
            "paths": sorted(
                _bucket(normalized_entries, "training_or_objective_document")
                + _bucket(normalized_entries, "learned_capability_document")
                + _bucket(normalized_entries, "training_runtime_artifact")
            ),
            "validation": [
                "artifact references a unique objective",
                "artifact references validation evidence",
                "artifact does not claim independent TOD capability when Codex authored it",
            ],
            "completion_evidence": "training artifact commit or archive/ignore decision",
        },
        {
            "slice_id": "local_or_generated_state_disposition",
            "owner": "TOD",
            "action": "archive_ignore_or_delete_only_after_snapshot_review",
            "risk": "low",
            "paths": sorted(
                _bucket(normalized_entries, "generated_runtime_artifact")
                + _bucket(normalized_entries, "local_state_backup")
                + _bucket(normalized_entries, "patch_packet_archive")
            ),
            "validation": [
                "confirm whether artifact is evidence-bearing",
                "move durable evidence into a reviewed artifact path or add ignore rule",
            ],
            "completion_evidence": "no generated state remains as anonymous dirt",
        },
        {
            "slice_id": "manual_governance_or_deletion_review",
            "owner": "Dave + MIM + TOD",
            "action": "explicit_review_before_staging",
            "risk": "high",
            "paths": sorted(
                _bucket(normalized_entries, "governance_document_change")
                + _bucket(normalized_entries, "deleted_path_review")
            ),
            "validation": [
                "CODEX.md changes reviewed as governance",
                "deleted path replacement or intentional removal is proven",
            ],
            "completion_evidence": "separate governance/deletion decision",
        },
    ]

    remaining_after_current_slice = max(
        len(normalized_entries) - len(current_codex_slice),
        0,
    )

    return {
        "ok": True,
        "objective_id": "TOD-WORKTREE-CLEANUP-EXECUTION-V1",
        "artifact_type": "tod_worktree_cleanup_execution_manifest",
        "generated_at": utc_now(),
        "source_artifact": str(DEFAULT_INPUT.relative_to(ROOT)),
        "intervention_class": "escalation_after_TOD_attempt",
        "tod_independent_capability_acquired": False,
        "training_debt": "TOD-WORKTREE-CLEANUP-EXECUTION-ASSIMILATION-V1",
        "non_destructive": True,
        "policy": {
            "cleanup_does_not_mean_revert": True,
            "stage_exact_paths_only": True,
            "secrets_never_staged": True,
            "generated_state_needs_disposition": True,
            "codex_authored_work_is_borrowed_capability": True,
        },
        "summary": {
            "input_paths": len(normalized_entries),
            "bucket_counts": dict(sorted(buckets.items())),
            "current_reviewed_slice_paths": len(current_codex_slice),
            "remaining_paths_after_current_slice": remaining_after_current_slice,
            "execution_slices": len(execution_slices),
        },
        "execution_slices": execution_slices,
        "blocked_from_automatic_cleanup": [
            "CODEX.md governance changes require explicit governance review.",
            "Deleted runtime listener path requires replacement or intentional-removal evidence.",
            "Large TOD control-plane changes must be split and validated before staging.",
            "Remote MIM product patches must be committed by feature, not swept together.",
            "Training artifacts must not claim independent TOD capability when Codex authored the implementation.",
        ],
        "next_required_action": "validate and commit only commit_current_codex_reviewed_slice, then hand remaining slices back to TOD with this manifest as the work order",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    classification = read_json(args.input)
    manifest = build_execution_manifest(classification)
    manifest["source_artifact"] = str(args.input)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {args.output} "
        f"({manifest['summary']['current_reviewed_slice_paths']} current-slice paths)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
