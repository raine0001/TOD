#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "shared_state" / "tod_sync_cleanliness.latest.json"
DEFAULT_OUTPUT = (
    ROOT
    / "runtime_remote_training"
    / "worktree_hygiene"
    / "TOD_WORKTREE_PATH_CLASSIFICATION_MATERIALIZER_V1.latest.json"
)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return payload


def normalize_path(path: str) -> str:
    return path.replace("\\", "/").strip()


def classify_path(path: str, status: str) -> dict[str, str]:
    p = normalize_path(path)
    lower = p.lower()
    status = status.strip() or "unknown"

    if p in {".env"} or lower.endswith(".env") or "/.env" in lower:
        return {
            "owner": "Dave + TOD",
            "bucket": "secret_or_local_environment",
            "action": "exclude_from_commit_and_review_local_secret_source",
            "risk": "high",
            "reason": "Environment and secret-bearing files must not be staged during hygiene cleanup.",
        }

    if status == "D":
        return {
            "owner": "TOD",
            "bucket": "deleted_path_review",
            "action": "verify_replacement_or_intent_before_staging_deletion",
            "risk": "high",
            "reason": "Deleted paths can remove runtime capability and need explicit intent evidence.",
        }

    if lower.startswith("runtime_remote_training/"):
        if any(
            segment in lower
            for segment in (
                "/read_only_audit_artifacts/",
                "/training_debt/",
                "/learned_capabilities/",
                "/remote_scripts/",
            )
        ):
            return {
                "owner": "TOD",
                "bucket": "training_runtime_artifact",
                "action": "archive_or_promote_intentional_artifact_then_ignore_generated_churn",
                "risk": "medium",
                "reason": "Runtime training outputs are evidence-bearing but should be promoted intentionally, not left as anonymous dirt.",
            }
        return {
            "owner": "TOD",
            "bucket": "generated_runtime_artifact",
            "action": "archive_or_ignore_generated_output_after_evidence_review",
            "risk": "low",
            "reason": "Generated runtime outputs should not keep the source tree dirty.",
        }

    if lower.startswith(("runtime/", "shared_state/", "tod/out/", "out/", "logs/", "history/")):
        return {
            "owner": "TOD",
            "bucket": "generated_or_shared_state",
            "action": "publish_required_evidence_then_ignore_or_archive_generated_state",
            "risk": "low",
            "reason": "Shared state and runtime telemetry are operational evidence, not broad source commits.",
        }

    if lower.startswith("tmp_remote_mim/"):
        return {
            "owner": "MIM + TOD",
            "bucket": "remote_mim_product_patch",
            "action": "split_into_reviewable_product_patch_with_tests_before_commit",
            "risk": "high",
            "reason": "Remote MIM mirror changes may be live product behavior and must be reviewed by feature slice.",
        }

    if lower.startswith("scripts/"):
        if lower.endswith(".ps1"):
            return {
                "owner": "TOD",
                "bucket": "tod_control_plane_script",
                "action": "review_diff_validate_control_plane_then_commit_or_split",
                "risk": "high",
                "reason": "TOD PowerShell control-plane changes affect execution, routing, or health loops.",
            }
        return {
            "owner": "TOD",
            "bucket": "tod_control_plane_tool",
            "action": "review_diff_run_focused_validation_then_commit_or_split",
            "risk": "medium",
            "reason": "TOD script/tool changes should be validated and grouped by capability.",
        }

    if lower.startswith("tools/"):
        return {
            "owner": "TOD",
            "bucket": "scorecard_or_audit_tool",
            "action": "review_tool_diff_run_unit_validation_then_commit_or_split",
            "risk": "medium",
            "reason": "Tools usually support scoring/audit publication and need validation evidence.",
        }

    if lower.startswith("tests/") or "/tests/" in lower:
        return {
            "owner": "TOD",
            "bucket": "validation_test_change",
            "action": "pair_with_matching_behavior_change_or_commit_as_regression_guard",
            "risk": "medium",
            "reason": "Test changes should either guard a specific behavior change or be a standalone regression slice.",
        }

    if lower.startswith("docs/training/learned-capabilities/"):
        return {
            "owner": "MIM + TOD",
            "bucket": "learned_capability_document",
            "action": "promote_if_supported_by_evidence_artifact_else_hold_for_review",
            "risk": "medium",
            "reason": "Capability freezes must be backed by validation evidence, not only narrative.",
        }

    if lower.startswith("docs/training/"):
        return {
            "owner": "MIM + TOD",
            "bucket": "training_or_objective_document",
            "action": "group_by_objective_and_commit_only_with_current_evidence",
            "risk": "medium",
            "reason": "Training documents should be grouped by objective so the worktree stays reviewable.",
        }

    if lower.startswith("docs/patch-packets/"):
        return {
            "owner": "TOD",
            "bucket": "patch_packet_archive",
            "action": "archive_or_link_to_executed_result_before_commit",
            "risk": "low",
            "reason": "Patch packets are useful evidence only when linked to execution results.",
        }

    if lower.startswith("tod/config/"):
        return {
            "owner": "TOD",
            "bucket": "tod_configuration_change",
            "action": "inspect_config_diff_validate_schema_then_commit_or_split",
            "risk": "high",
            "reason": "TOD config changes can alter active project/task routing.",
        }

    if lower.startswith("tod/data/") and lower.endswith(".bak"):
        return {
            "owner": "TOD",
            "bucket": "local_state_backup",
            "action": "move_to_ignored_backup_location_or_delete_only_after_snapshot_review",
            "risk": "low",
            "reason": "State backups are local recovery artifacts and usually should not be committed.",
        }

    if lower == "codex.md":
        return {
            "owner": "Dave + MIM + TOD",
            "bucket": "governance_document_change",
            "action": "review_explicitly_and_commit_only_as_governance_slice",
            "risk": "high",
            "reason": "CODEX.md defines operating authority and should not be swept into unrelated commits.",
        }

    return {
        "owner": "MIM + TOD",
        "bucket": "review_required_unknown",
        "action": "inspect_diff_and_assign_to_a_smaller_owner_bucket_before_cleanup",
        "risk": "medium",
        "reason": "No deterministic hygiene rule matched this path.",
    }


def build_manifest(cleanliness: dict[str, Any]) -> dict[str, Any]:
    items = cleanliness.get("items")
    paths = cleanliness.get("remaining_dirty_paths")

    if isinstance(items, list) and items:
        raw_items = [
            {
                "path": normalize_path(str(item.get("path") or "")),
                "status": str(item.get("status") or ""),
            }
            for item in items
            if isinstance(item, dict) and str(item.get("path") or "").strip()
        ]
    elif isinstance(paths, list):
        raw_items = [{"path": normalize_path(str(path)), "status": ""} for path in paths]
    else:
        raise ValueError("Input must contain items or remaining_dirty_paths")

    seen: set[str] = set()
    classified = []
    duplicates = []
    for item in raw_items:
        path = item["path"]
        if path in seen:
            duplicates.append(path)
            continue
        seen.add(path)
        classification = classify_path(path, item["status"])
        classified.append(
            {
                "path": path,
                "git_status": item["status"] or "unknown",
                **classification,
            }
        )

    bucket_counts = Counter(entry["bucket"] for entry in classified)
    owner_counts = Counter(entry["owner"] for entry in classified)
    action_counts = Counter(entry["action"] for entry in classified)
    unclassified = [entry for entry in classified if entry["bucket"] == "review_required_unknown"]

    return {
        "ok": len(unclassified) == 0 and not duplicates,
        "objective_id": "TOD-WORKTREE-PATH-CLASSIFICATION-MATERIALIZER-V1",
        "artifact_type": "tod_worktree_path_classification_manifest",
        "generated_at": utc_now(),
        "source_artifact": str(DEFAULT_INPUT.relative_to(ROOT))
        if DEFAULT_INPUT.exists()
        else "shared_state/tod_sync_cleanliness.latest.json",
        "intervention_class": "escalation_after_TOD_attempt",
        "tod_independent_capability_acquired": False,
        "training_debt": "TOD-WORKTREE-PATH-CLASSIFICATION-MATERIALIZER-ASSIMILATION-V1",
        "non_destructive": True,
        "source_modified": False,
        "summary": {
            "total_paths": len(raw_items),
            "classified_paths": len(classified),
            "duplicate_paths_skipped": len(duplicates),
            "unclassified_paths": len(unclassified),
            "bucket_counts": dict(sorted(bucket_counts.items())),
            "owner_counts": dict(sorted(owner_counts.items())),
            "action_counts": dict(sorted(action_counts.items())),
        },
        "next_slices": [
            {
                "slice": "governance_and_tod_control_plane",
                "buckets": [
                    "governance_document_change",
                    "tod_control_plane_script",
                    "tod_control_plane_tool",
                    "tod_configuration_change",
                ],
                "rule": "Review exact diffs, run focused validation, and commit only coherent control-plane changes.",
            },
            {
                "slice": "remote_mim_product_patch",
                "buckets": ["remote_mim_product_patch"],
                "rule": "Split live-product mirror edits by feature and test before deploy.",
            },
            {
                "slice": "training_memory_and_evidence",
                "buckets": [
                    "training_or_objective_document",
                    "learned_capability_document",
                    "training_runtime_artifact",
                ],
                "rule": "Promote only artifacts with validation evidence; archive or ignore generated churn.",
            },
            {
                "slice": "local_generated_state",
                "buckets": [
                    "generated_runtime_artifact",
                    "generated_or_shared_state",
                    "local_state_backup",
                ],
                "rule": "Do not commit by default; archive or add ignore rules after evidence review.",
            },
        ],
        "validation": {
            "every_input_path_has_bucket_owner_action": all(
                entry.get("bucket") and entry.get("owner") and entry.get("action")
                for entry in classified
            ),
            "all_paths_represented_once": len(classified) + len(duplicates) == len(raw_items),
            "source_dirty_count_before": cleanliness.get("dirty_count_before"),
            "source_remaining_dirty_count": cleanliness.get("remaining_dirty_count"),
        },
        "duplicates": duplicates,
        "unclassified": unclassified,
        "paths": classified,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    cleanliness = read_json(args.input)
    manifest = build_manifest(cleanliness)
    manifest["source_artifact"] = str(args.input)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {args.output} "
        f"({manifest['summary']['classified_paths']}/{manifest['summary']['total_paths']} classified)"
    )
    return 0 if manifest["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
