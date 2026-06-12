from __future__ import annotations

import json
from pathlib import Path

from core.interaction_quality_dashboard import build_interaction_quality_snapshot


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def test_interaction_quality_snapshot_reads_smoke_artifacts(tmp_path: Path):
    eval_root = tmp_path / "runtime" / "shared" / "conversation_eval"
    _write_json(
        eval_root / "universal_mim_customer_conversation_smoke.latest.json",
        {
            "schema_version": "UNIVERSAL-MIM-CUSTOMER-CONVERSATION-SMOKE-V1",
            "generated_at": "2026-06-12T02:10:27Z",
            "scenario_count_per_surface": 3,
            "rollup": {
                "weighted_pass_rate": 0.96,
                "internal_jargon_failure_count": 0,
                "passes_threshold": True,
            },
            "surfaces": [
                {
                    "surface": "mimtod_public_chat",
                    "available": True,
                    "summary": {
                        "scenario_count": 3,
                        "passed_count": 3,
                        "failure_count": 0,
                        "weighted_pass_rate": 1.0,
                    },
                    "runs": [],
                },
                {
                    "surface": "agentmim_logged_in_assistant",
                    "available": False,
                    "unavailable_reason": "auth_required",
                    "summary": {"scenario_count": 0},
                    "runs": [],
                },
            ],
        },
    )

    snapshot = build_interaction_quality_snapshot(project_root=tmp_path)

    assert snapshot["schema_version"] == "mim-interaction-quality-dashboard-v1"
    assert snapshot["headline"]["available_artifacts"] == 1
    assert snapshot["headline"]["best_weighted_pass_rate"] == 0.96
    assert snapshot["artifacts"][0]["surfaces"][0]["surface"] == "mimtod_public_chat"
    assert snapshot["next_actions"][0]["action"] == "Authorize and run logged-in AgentMIM surface certification."


def test_interaction_quality_snapshot_groups_failures(tmp_path: Path):
    eval_root = tmp_path / "runtime" / "shared" / "conversation_eval"
    _write_json(
        eval_root / "public_mim_customer_conversation_smoke.latest.json",
        {
            "summary": {
                "generated_at": "2026-06-12T01:29:26Z",
                "scenario_count": 2,
                "weighted_pass_rate": 0.5,
            },
            "runs": [
                {
                    "scenario_id": "case-1",
                    "bucket": "conversion_intent",
                    "passed": False,
                    "failures": ["conversion_next_step_missing", "internal_jargon_leakage"],
                    "turns": [{"turn": "Can I try this?", "reply": "artifact id 123"}],
                }
            ],
        },
    )

    snapshot = build_interaction_quality_snapshot(project_root=tmp_path)
    families = {row["family"]: row["count"] for row in snapshot["failure_analysis"]["family_counts"]}

    assert families["conversion"] == 1
    assert families["internal_jargon"] == 1
    assert snapshot["failure_analysis"]["examples"][0]["bucket"] == "conversion_intent"
