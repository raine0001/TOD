"""Build MIM Operator Impact scorecard from recent training replies."""
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import re
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"
SCOREBOARD_PATH = TRAINING_ROOT / "MIM_TOD_TRAINING_SCOREBOARD.latest.json"
LIVE_10_PATH = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
STRUCTURAL_PATH = TRAINING_ROOT / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"
CROSS_SURFACE_PATH = TRAINING_ROOT / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"
CONTEXT_GROUNDING_PATH = TRAINING_ROOT / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"
OUTCOME_BINDING_PATH = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json"
OUTPUT_PATH = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json"
OUTPUT_MD_PATH = TRAINING_ROOT / "MIM_OPERATOR_IMPACT_SCORECARD.latest.md"

FIELD_RULES = {
    "actionability": re.compile(r"\b(next step|next action|action:|recommended action|recommendation:|i recommend|should)\b", re.I),
    "owner_assignment": re.compile(r"\b(owner|MIM|TOD|Codex|Dave|external dependency)\b", re.I),
    "expected_evidence": re.compile(r"\b(evidence|artifact|result|proof|validation|reflection|scoreboard|record)\b", re.I),
    "time_aging_rule": re.compile(r"\b(hour|daily|weekly|24h|72h|7d|aging|stale|rerun|after the next)\b", re.I),
    "dave_needed": re.compile(r"\b(Dave needed|Dave is needed|Dave is not needed|Dave: yes|Dave: no|no Dave|unless .+Dave)\b", re.I),
}


def _load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _percent(passed: int, total: int) -> int:
    return round((passed / total) * 100) if total > 0 else 0


def _metric_row(metric: str, baseline: str, current: str, source: str) -> dict[str, str]:
    return {"metric": metric, "baseline": baseline, "current": current, "source": source}


def _structural_metric_rows() -> list[dict[str, str]]:
    structural = _load_json(STRUCTURAL_PATH)
    cross_surface = _load_json(CROSS_SURFACE_PATH)
    context_grounding = _load_json(CONTEXT_GROUNDING_PATH)
    if not structural:
        rows = [
            _metric_row(
                "Structural Reasoning Diversity",
                "new metric",
                "needs scorecard run",
                "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json",
            )
        ]
        if not cross_surface:
            rows.append(
                _metric_row(
                    "Structural Reasoning Cross-Surface Propagation",
                    "new metric",
                    "needs scorecard run",
                    "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json",
                )
            )
        if context_grounding:
            grounding_pass = context_grounding.get("weighted_pass_rate")
            if isinstance(grounding_pass, (int, float)):
                current_grounding = (
                    f"{round(float(grounding_pass) * 100)}% weighted pass; "
                    f"score {context_grounding.get('weighted_context_score', 'unknown')}/10"
                )
            else:
                current_grounding = f"{context_grounding.get('status', 'unknown')}; score {context_grounding.get('weighted_context_score', 'unknown')}/10"
        else:
            current_grounding = "needs scorecard run"
        rows.append(
            _metric_row(
                "Context-Grounded Conversation",
                "new metric",
                current_grounding,
                "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json",
            )
        )
        return rows
    weighted = structural.get("weighted_pass_rate")
    if isinstance(weighted, (int, float)):
        current = f"{round(float(weighted) * 100)}% weighted pass; score {structural.get('weighted_structural_score', 'unknown')}/10"
    else:
        current = f"{structural.get('status', 'unknown')}; score {structural.get('weighted_structural_score', 'unknown')}/10"
    rows = [
        _metric_row(
            "Structural Reasoning Diversity",
            "new metric",
            current,
            "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json",
        ),
        _metric_row(
            "Premature Closure Resistance",
            "new metric",
            str(next((row.get("pass_rate") for row in structural.get("metrics", []) if isinstance(row, dict) and row.get("metric") == "no_false_closure"), "needs proof")),
            "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json",
        ),
        _metric_row(
            "Evidence Boundary Discipline",
            "new metric",
            str(next((row.get("pass_rate") for row in structural.get("metrics", []) if isinstance(row, dict) and row.get("metric") == "evidence_boundary"), "needs proof")),
            "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json",
        ),
    ]
    if cross_surface:
        target_met = cross_surface.get("target_met_surface_count")
        surface_count = cross_surface.get("surface_count")
        surface_bits = []
        for surface in cross_surface.get("surfaces") or []:
            if not isinstance(surface, dict):
                continue
            summary = surface.get("summary") if isinstance(surface.get("summary"), dict) else {}
            surface_bits.append(f"{surface.get('surface')}={summary.get('weighted_pass_rate')}")
        current_cross = (
            f"{cross_surface.get('status', 'unknown')}; {target_met}/{surface_count} surfaces target met"
        )
        if surface_bits:
            current_cross = f"{current_cross}; " + ", ".join(surface_bits[:5])
    else:
        current_cross = "needs scorecard run"
    rows.append(
        _metric_row(
            "Structural Reasoning Cross-Surface Propagation",
            "new metric",
            current_cross,
            "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json",
        )
    )
    if context_grounding:
        grounding_pass = context_grounding.get("weighted_pass_rate")
        if isinstance(grounding_pass, (int, float)):
            current_grounding = (
                f"{round(float(grounding_pass) * 100)}% weighted pass; "
                f"score {context_grounding.get('weighted_context_score', 'unknown')}/10"
            )
        else:
            current_grounding = f"{context_grounding.get('status', 'unknown')}; score {context_grounding.get('weighted_context_score', 'unknown')}/10"
    else:
        current_grounding = "needs scorecard run"
    rows.append(
        _metric_row(
            "Context-Grounded Conversation",
            "new metric",
            current_grounding,
            "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json",
        )
    )
    return rows


def _outcome_binding_metric_rows() -> list[dict[str, str]]:
    binding = _load_json(OUTCOME_BINDING_PATH)
    if not binding:
        return [
            _metric_row(
                "Recommended Next Action Accuracy",
                "new metric",
                "outcome binding not run",
                "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json",
            ),
            _metric_row(
                "Expected Evidence Observed",
                "new metric",
                "outcome binding not run",
                "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json",
            ),
        ]
    sample_count = int(binding.get("sample_count") or 0)
    observed = int(binding.get("observed_artifact_count") or 0)
    pending = int(binding.get("pending_observation_count") or 0)
    expected = int(binding.get("expected_evidence_count") or 0)
    status = str(binding.get("status") or "unknown")
    return [
        _metric_row(
            "Recommended Next Action Accuracy",
            "new metric",
            f"{status}; {pending} pending movement checks",
            "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json",
        ),
        _metric_row(
            "Expected Evidence Observed",
            "new metric",
            f"{observed}/{sample_count} replies have observable named artifacts; {expected} state expected evidence",
            "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json",
        ),
    ]


def build_scorecard() -> dict[str, Any]:
    live_10 = _load_json(LIVE_10_PATH)
    live_10_metrics = live_10.get("metrics") if isinstance(live_10.get("metrics"), list) else []
    live_10_has_required_shape = (
        live_10.get("packet_type") == "mim-operator-impact-live-10-scorecard-v1"
        or (
            isinstance(live_10.get("operator_impact_score"), (int, float))
            and isinstance(live_10.get("sample_count"), int)
            and isinstance(live_10.get("pass_count"), int)
            and bool(live_10_metrics)
        )
    )
    if live_10_has_required_shape and live_10.get("sample_count"):
        generated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        sample_count = int(live_10.get("sample_count") or 0)
        pass_count = int(live_10.get("pass_count") or 0)
        operator_impact_score = float(live_10.get("operator_impact_score") or 0.0)
        live_10_target_met = (
            live_10.get("status") == "target_met"
            or (sample_count >= 10 and pass_count == sample_count and operator_impact_score >= 8)
        )
        metrics = []
        for row in live_10_metrics:
            if not isinstance(row, dict):
                continue
            metrics.append(
                _metric_row(
                    str(row.get("metric") or ""),
                    str(row.get("baseline") or "live-10 baseline"),
                    str(row.get("current") or ""),
                    str(row.get("source") or "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"),
                )
            )
        metrics.extend(
            [
                *_structural_metric_rows(),
                *_outcome_binding_metric_rows(),
                _metric_row("Project Momentum Created", "new metric needed", "needs attribution", "count projects moved by MIM-selected actions"),
                _metric_row("Unnecessary Status Responses", "baseline established", "live-10 contract enforced", "track when MIM reports status without a useful action"),
                _metric_row("Dave Intervention Avoidance", "new metric needed", "needs attribution", "track MIM/TOD/Codex resolution before asking Dave"),
                _metric_row("Continuity Lookup Usage", "new metric needed", "needs proof", "score whether MIM loads prior project history before implementation"),
                _metric_row("Project Advancement Rate", "new metric needed", "needs outcome-linked proof", "measure projects moved to accepted, split, archived, dispatched, or waiting-with-evidence"),
                _metric_row("Prevented Waste", "new metric needed", "needs proof", "track scope splits, duplicate work prevented, reused prior solutions, and continuity saves"),
            ]
        )
        return {
            "packet_type": "mim-operator-impact-scorecard-v1",
            "generated_at": generated_at,
            "status": "target_met" if live_10_target_met else "measured_contract_fields",
            "sample_count": sample_count,
            "pass_count": pass_count,
            "required_fields": list(live_10.get("required_fields") or FIELD_RULES.keys()),
            "operator_impact_percent": int(live_10.get("operator_impact_percent") or 0),
            "operator_impact_score": operator_impact_score,
            "target_score": 8,
            "source_files": [str(LIVE_10_PATH)],
            "metrics": metrics,
            "scored_cases": live_10.get("scored_cases") if isinstance(live_10.get("scored_cases"), list) else [],
            "next_action": "Bind expected evidence to observed project/successor records, then rerun live scoring within 24 hours.",
        }

    scoreboard = _load_json(SCOREBOARD_PATH)
    cases = scoreboard.get("mim_score", {}).get("evaluation", {}).get("cases", [])
    cases = [case for case in cases if isinstance(case, dict)]
    scored_cases: list[dict[str, Any]] = []
    field_counts = {key: 0 for key in FIELD_RULES}

    for case in cases:
        reply = str(case.get("reply_excerpt") or "")
        field_scores = {key: bool(pattern.search(reply)) for key, pattern in FIELD_RULES.items()}
        for key, passed in field_scores.items():
            if passed:
                field_counts[key] += 1
        scored_cases.append(
            {
                "id": case.get("id"),
                "prompt": case.get("prompt"),
                "reply_excerpt": reply[:500],
                "field_scores": field_scores,
                "passed_field_count": sum(1 for passed in field_scores.values() if passed),
                "required_field_count": len(FIELD_RULES),
            }
        )

    sample_count = len(scored_cases)
    total_field_passes = sum(field_counts.values())
    total_possible = sample_count * len(FIELD_RULES)
    operator_impact_percent = _percent(total_field_passes, total_possible)
    operator_impact_tenths = round(operator_impact_percent / 10, 1)

    def field_current(field_key: str) -> str:
        passed = field_counts.get(field_key, 0)
        return f"{_percent(passed, sample_count)}% / {passed} of {sample_count}" if sample_count else "0% / 0 of 0"

    metrics = [
        _metric_row("Operator Impact", "6/10", f"{operator_impact_tenths}/10 from {sample_count} scored replies", "live/replayed MIM replies scored for action, owner, evidence, aging rule, Dave-needed"),
        _metric_row("Actionability Score", "baseline established", field_current("actionability"), "specific recommended action present"),
        _metric_row("Owner Assignment", "baseline established", field_current("owner_assignment"), "reply names MIM, TOD, Codex, external dependency, or Dave"),
        _metric_row("Expected Evidence", "baseline established", field_current("expected_evidence"), "reply states artifact/result/proof/validation expected"),
        _metric_row("Time / Aging Rule", "baseline established", field_current("time_aging_rule"), "reply includes follow-up timing, stale threshold, or rerun/escalation timing"),
        _metric_row("Dave Needed Clarity", "baseline established", field_current("dave_needed"), "reply says whether Dave is needed or states the exception"),
        *_structural_metric_rows(),
        *_outcome_binding_metric_rows(),
        _metric_row("Project Momentum Created", "new metric needed", "needs attribution", "count projects moved by MIM-selected actions"),
        _metric_row("Unnecessary Status Responses", "baseline established", f"{sample_count - field_counts.get('actionability', 0)} possible misses", "track when MIM reports status without a useful action"),
        _metric_row("Dave Intervention Avoidance", "new metric needed", "needs attribution", "track MIM/TOD/Codex resolution before asking Dave"),
        _metric_row("Continuity Lookup Usage", "new metric needed", "needs proof", "score whether MIM loads prior project history before implementation"),
        _metric_row("Project Advancement Rate", "new metric needed", "needs outcome-linked proof", "measure projects moved to accepted, split, archived, dispatched, or waiting-with-evidence"),
        _metric_row("Prevented Waste", "new metric needed", "needs proof", "track scope splits, duplicate work prevented, reused prior solutions, and continuity saves"),
    ]
    generated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return {
        "packet_type": "mim-operator-impact-scorecard-v1",
        "generated_at": generated_at,
        "status": "measured_contract_fields" if sample_count else "no_samples",
        "sample_count": sample_count,
        "required_fields": list(FIELD_RULES.keys()),
        "operator_impact_percent": operator_impact_percent,
        "operator_impact_score": operator_impact_tenths,
        "target_score": 8,
        "source_files": [str(SCOREBOARD_PATH)],
        "structural_reasoning_source": str(STRUCTURAL_PATH),
        "metrics": metrics,
        "scored_cases": scored_cases,
        "next_action": "Score the next 10 live operational MIM replies, then bind expected evidence to observed project/successor records.",
    }


def write_outputs(scorecard: dict[str, Any]) -> None:
    OUTPUT_PATH.write_text(json.dumps(scorecard, indent=2, sort_keys=True), encoding="utf-8")
    lines = [
        "# MIM Operator Impact Scorecard",
        "",
        f"Generated: {scorecard.get('generated_at')}",
        f"Status: {scorecard.get('status')}",
        f"Operator impact: {scorecard.get('operator_impact_score')}/10",
        f"Samples: {scorecard.get('sample_count')}",
        "",
        "## Metrics",
        "",
    ]
    for row in scorecard.get("metrics", []):
        lines.append(f"- {row.get('metric')}: {row.get('current')} ({row.get('source')})")
    lines.extend(["", f"Next action: {scorecard.get('next_action')}"])
    OUTPUT_MD_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    scorecard = build_scorecard()
    write_outputs(scorecard)
    print(f"Wrote {OUTPUT_PATH}")
    print(f"Wrote {OUTPUT_MD_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
