#!/usr/bin/env python3
"""Generate a verifiable MIM/TOD training scoreboard from artifacts.

The scoreboard intentionally separates measured metrics from metrics that still
need instrumentation. It can optionally run a small live MIM response evaluation
against /gateway/intake to produce today's communication scores.
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"
BLOCKER_ROOT = TRAINING_ROOT / "blocked_objective_training"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def pct(numerator: int, denominator: int) -> int | None:
    if denominator <= 0:
        return None
    return round((numerator / denominator) * 100)


def baseline_needed(reason: str) -> dict[str, Any]:
    return {"value": None, "status": "baseline_needed", "reason": reason}


def sanitize_operator_text(value: Any) -> str:
    text = str(value or "")
    text = re.sub(r"\btask\s+\d{3,}\b", "the inspected task", text, flags=re.IGNORECASE)
    text = re.sub(r"\bobjective\s+\d{3,}\b", "the inspected objective", text, flags=re.IGNORECASE)
    text = re.sub(r"\bobjective-\d+\b", "the active objective", text, flags=re.IGNORECASE)
    text = re.sub(r"\brecommendation\s+\d{2,}\b", "the newest improvement recommendation", text, flags=re.IGNORECASE)
    return text


def post_gateway(base_url: str, prompt: str) -> str:
    payload = {
        "source": "text",
        "raw_input": prompt,
        "parsed_intent": "question",
        "confidence": 0.99,
        "target_system": "MIM",
        "requested_goal": "",
        "safety_flags": [],
        "metadata_json": {
            "route_preference": "conversation_layer",
            "test": "training_scoreboard_eval",
        },
    }
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/gateway/intake",
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    mim_interface = data.get("mim_interface") if isinstance(data.get("mim_interface"), dict) else {}
    resolution = data.get("resolution") if isinstance(data.get("resolution"), dict) else {}
    return str(mim_interface.get("reply_text") or resolution.get("clarification_prompt") or "").strip()


def evaluate_mim(base_url: str | None) -> dict[str, Any]:
    prompts = [
        {
            "id": "training_status",
            "prompt": "how is training going MIM?",
            "expected": ["training", "mim", "tod", "blocker"],
            "recommendation": False,
        },
        {
            "id": "blockers",
            "prompt": "any blockers?",
            "expected": ["blocker", "next", "dave"],
            "recommendation": False,
        },
        {
            "id": "next_work",
            "prompt": "is there anything you want to work on next?",
            "expected": ["next", "why", "intent"],
            "recommendation": True,
        },
        {
            "id": "more_training",
            "prompt": "tell me more about your training MIM",
            "expected": ["training", "mim", "tod"],
            "recommendation": False,
        },
    ]
    bad_generic = (
        "let me know if you want",
        "ask me about",
        "i can answer that directly",
        "what would you like to explore",
    )
    jargon_patterns = (
        r"\brequest[_ -]?id\b",
        r"\blifecycle\b",
        r"\bpacket\b",
        r"\bGET\s+/",
        r"\bpass bar\b",
        r"\bcontinuation policy\b",
        r"\bobjective-\d+\b",
        r"\btask\s+\d{3,}\b",
    )
    results: list[dict[str, Any]] = []
    if not base_url:
        return {
            "status": "baseline_needed",
            "reason": "live gateway evaluation was not requested",
            "cases": [],
        }
    for item in prompts:
        prompt = str(item["prompt"])
        try:
            reply = post_gateway(base_url, prompt)
            normalized = " ".join(reply.lower().split())
            expected = [str(token).lower() for token in item["expected"]]
            intent_understood = all(token in normalized for token in expected)
            answered = bool(reply) and len(reply) >= 80 and not any(marker in normalized for marker in bad_generic)
            jargon_hits = [
                pattern
                for pattern in jargon_patterns
                if re.search(pattern, reply, flags=re.IGNORECASE)
            ]
            recommendation_quality = (
                not bool(item["recommendation"])
                or ("why" in normalized and "next" in normalized and not jargon_hits)
            )
            results.append(
                {
                    "id": item["id"],
                    "prompt": prompt,
                    "reply_length": len(reply),
                    "intent_understood": intent_understood,
                    "answered_question": answered,
                    "internal_jargon_hits": jargon_hits,
                    "recommendation_quality": recommendation_quality,
                    "reply_excerpt": reply[:280],
                }
            )
        except Exception as exc:
            results.append(
                {
                    "id": item["id"],
                    "prompt": prompt,
                    "error": " ".join(str(exc).split())[:240],
                    "intent_understood": False,
                    "answered_question": False,
                    "internal_jargon_hits": ["evaluation_error"],
                    "recommendation_quality": False,
                }
            )
    if results and all(row.get("error") for row in results):
        return {
            "status": "live_eval_unavailable",
            "reason": "all live gateway evaluation prompts failed",
            "case_count": len(results),
            "cases": results,
        }
    total = len(results)
    intent_pass = sum(1 for row in results if row.get("intent_understood"))
    answer_pass = sum(1 for row in results if row.get("answered_question"))
    jargon_count = sum(1 for row in results if row.get("internal_jargon_hits"))
    rec_cases = [row for row in results if row["id"] == "next_work"]
    rec_pass = sum(1 for row in rec_cases if row.get("recommendation_quality"))
    return {
        "status": "measured",
        "case_count": total,
        "metrics": {
            "intent_understood_percent": pct(intent_pass, total),
            "answered_question_percent": pct(answer_pass, total),
            "internal_jargon_rate_percent": pct(jargon_count, total),
            "recommendation_quality_percent": pct(rec_pass, len(rec_cases)),
        },
        "cases": results,
    }


def build_scoreboard(base_url: str | None, operator_estimated_hours: float | None) -> dict[str, Any]:
    directive = load_json(TRAINING_ROOT / "MIM_TOD_CONTINUOUS_TRAINING_DIRECTIVE.latest.json")
    reflection = load_json(TRAINING_ROOT / "MIM_TOD_HOURLY_REFLECTION.latest.json")
    durability_v2 = load_json(TRAINING_ROOT / "MIM_DURABILITY_SMOKE_V2.latest.json")
    drill2 = load_json(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_CLEARING_DRILL_002.latest.json")
    drill3 = load_json(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_003.latest.json")
    drill4 = load_json(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_004.latest.json")
    triage = load_json(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_TRIAGE.latest.json")
    previous_scoreboard = load_json(TRAINING_ROOT / "MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    mim_eval = evaluate_mim(base_url)

    active_drill = ((directive.get("tod_training") or {}).get("active_blocker_clearing_drill") or {})
    blocked_start = (
        active_drill.get("blocked_total_at_start")
        or drill3.get("blocked_total_at_start")
        or drill2.get("blocked_total_at_start")
        or drill4.get("before_blocked_count")
    )
    after_candidates = [
        active_drill.get("after_blocked_count"),
        drill4.get("after_blocked_count"),
        drill3.get("after_blocked_count"),
        drill2.get("after_blocked_count"),
    ]
    numeric_after: list[int] = []
    for candidate in after_candidates:
        try:
            if candidate is not None:
                numeric_after.append(int(candidate))
        except Exception:
            pass
    blocked_after = min(numeric_after) if numeric_after else None
    blockers_cleared = None
    try:
        if blocked_start is not None and blocked_after is not None:
            blockers_cleared = int(blocked_start) - int(blocked_after)
    except Exception:
        blockers_cleared = None

    meaningful_inspection = bool(((drill4.get("validation") or {}).get("meaningful_result_detected")))
    false_completion_prevented = 1 if meaningful_inspection else 0
    no_op_rejections = baseline_needed("no-op rejection events are not yet counted in a daily metric artifact")
    validated_edits = baseline_needed("validated edit count needs task-result aggregation by day")

    mim_metrics_today = mim_eval.get("metrics", {}) if mim_eval.get("status") == "measured" else {}
    mim_metric_source = "live_gateway_eval" if mim_eval.get("status") == "measured" else "baseline_needed"
    if mim_eval.get("status") == "live_eval_unavailable":
        previous_mim = previous_scoreboard.get("mim_score") if isinstance(previous_scoreboard.get("mim_score"), dict) else {}
        previous_eval = previous_mim.get("evaluation") if isinstance(previous_mim.get("evaluation"), dict) else {}
        previous_metrics = previous_mim.get("metrics") if isinstance(previous_mim.get("metrics"), dict) else {}
        recovered: dict[str, Any] = {}
        previous_cases = previous_eval.get("cases") if isinstance(previous_eval.get("cases"), list) else []
        previous_all_errors = bool(previous_cases) and all(
            isinstance(row, dict) and row.get("error") for row in previous_cases
        )
        if previous_eval.get("status") == "measured" and not previous_all_errors:
            for metric_key, previous_key in {
                "intent_understood_percent": "intent_understood",
                "answered_question_percent": "answered_question",
                "internal_jargon_rate_percent": "internal_jargon",
                "recommendation_quality_percent": "recommendation_quality",
            }.items():
                previous_item = previous_metrics.get(previous_key) if isinstance(previous_metrics.get(previous_key), dict) else {}
                previous_today = previous_item.get("today")
                if not isinstance(previous_today, dict) and previous_today is not None:
                    recovered[metric_key] = previous_today
        if recovered:
            mim_metrics_today = recovered
            mim_metric_source = "previous_measured_score_preserved_live_eval_unavailable"
    latest_finding = sanitize_operator_text(drill4.get("correction") or drill4.get("current_finding"))
    freshness = reflection.get("freshness") if isinstance(reflection.get("freshness"), dict) else {}
    truth_integrity = (
        reflection.get("truth_integrity")
        if isinstance(reflection.get("truth_integrity"), dict)
        else {}
    )
    reflection_recommendations = reflection.get("recommendations")
    if not isinstance(reflection_recommendations, list):
        reflection_recommendations = []
    outcome_reflection = {
        "source": str(TRAINING_ROOT / "MIM_TOD_HOURLY_REFLECTION.latest.json"),
        "generated_at": reflection.get("generated_at"),
        "assessment": reflection.get("assessment") or "unknown",
        "are_they_improving": reflection.get("are_they_improving"),
        "are_they_creating_new_objectives": reflection.get("are_they_creating_new_objectives"),
        "truth_integrity_status": truth_integrity.get("status") or "unknown",
        "fresh_artifact_count": freshness.get("fresh_artifact_count"),
        "stale_artifact_count": len(freshness.get("stale_artifacts") or []),
        "stale_artifacts": freshness.get("stale_artifacts") or [],
        "operator_summary": sanitize_operator_text(reflection.get("operator_summary")),
        "recommendations": [sanitize_operator_text(item) for item in reflection_recommendations],
    }
    reflection_says_not_improving = outcome_reflection["are_they_improving"] is False
    durability_summary = (
        durability_v2.get("summary") if isinstance(durability_v2.get("summary"), dict) else {}
    )
    durability_groups = (
        durability_v2.get("group_summary")
        if isinstance(durability_v2.get("group_summary"), dict)
        else {}
    )
    judgment_mode_score = {
        "source": str(TRAINING_ROOT / "MIM_DURABILITY_SMOKE_V2.latest.json"),
        "objective_id": durability_v2.get("objective_id") or "MIM-DURABILITY-SMOKE-V2",
        "status": durability_v2.get("status") or "unknown",
        "generated_at": durability_v2.get("generated_at"),
        "case_count": durability_summary.get("case_count"),
        "passed": durability_summary.get("passed"),
        "failed": durability_summary.get("failed"),
        "pass_rate_percent": durability_summary.get("pass_rate_percent"),
        "group_summary": durability_groups,
        "current_weakness": "MIM defaults to status reporting instead of selecting recommendation, explanation, demonstration, consultative discovery, or problem-analysis mode.",
        "target": "Reach at least 80% on the focused V2 judgment suite before expanding to larger prompt sets.",
    }
    judgment_needs_attention = (
        isinstance(judgment_mode_score.get("pass_rate_percent"), (int, float))
        and float(judgment_mode_score["pass_rate_percent"]) < 80.0
    )
    scoreboard = {
        "packet_type": "mim-tod-training-scoreboard-v1",
        "generated_at": utc_now(),
        "status": (
            "needs_attention_with_training_active"
            if reflection_says_not_improving or judgment_needs_attention
            else "active_with_partial_metrics"
        ),
        "outcome_reflection": outcome_reflection,
        "judgment_mode_score": judgment_mode_score,
        "training_hours": {
            "last_7_days": baseline_needed("hourly training snapshots start with this scoreboard; prior exact hours are not reconstructable from latest-only files"),
            "yesterday": baseline_needed("daily training-hour snapshot did not exist yesterday"),
            "today": {
                "value": operator_estimated_hours,
                "status": "operator_estimate" if operator_estimated_hours is not None else "baseline_needed",
                "reason": "operator reported approximate continuous run; exact tracking begins with scoreboard v1",
            },
        },
        "mim_score": {
            "metrics": {
                "intent_understood": {
                    "yesterday": baseline_needed("no prior daily MIM communication eval"),
                    "today": mim_metrics_today.get("intent_understood_percent"),
                    "unit": "percent",
                    "source": mim_metric_source,
                },
                "answered_question": {
                    "yesterday": baseline_needed("no prior daily MIM communication eval"),
                    "today": mim_metrics_today.get("answered_question_percent"),
                    "unit": "percent",
                    "source": mim_metric_source,
                },
                "internal_jargon": {
                    "yesterday": baseline_needed("no prior daily MIM communication eval"),
                    "today": mim_metrics_today.get("internal_jargon_rate_percent"),
                    "unit": "percent_rate_lower_is_better",
                    "source": mim_metric_source,
                },
                "recommendation_quality": {
                    "yesterday": baseline_needed("no prior daily MIM communication eval"),
                    "today": mim_metrics_today.get("recommendation_quality_percent"),
                    "unit": "percent",
                    "source": mim_metric_source,
                },
            },
            "evaluation": mim_eval,
        },
        "tod_score": {
            "metrics": {
                "blockers_cleared": {
                    "yesterday": baseline_needed("no prior daily blocker scoreboard"),
                    "today": blockers_cleared,
                    "unit": "count",
                    "source": "blocker_drill_artifacts",
                },
                "false_completions_prevented": {
                    "yesterday": baseline_needed("no prior daily false-completion scoreboard"),
                    "today": false_completion_prevented,
                    "unit": "count",
                    "source": "drill_004_meaningful_evidence_self_correction",
                },
                "validated_edits": {
                    "yesterday": baseline_needed("no prior daily validated-edit scoreboard"),
                    "today": validated_edits,
                    "unit": "count",
                    "source": "baseline_needed",
                },
                "no_op_rejections": {
                    "yesterday": baseline_needed("no prior daily no-op rejection scoreboard"),
                    "today": no_op_rejections,
                    "unit": "count",
                    "source": "baseline_needed",
                },
            },
            "blocker_classes": (((directive.get("tod_training") or {}).get("active_blocker_clearing_drill") or {}).get("classes") or triage.get("classes") or {}),
            "latest_drill": {
                "id": drill4.get("drill_id"),
                "status": drill4.get("status"),
                "generated_at": drill4.get("generated_at"),
                "finding": latest_finding,
                "lesson": drill4.get("tod_lesson"),
            },
        },
        "recommendation": {
            "continue_training": True,
            "next_required_improvement": (
                "Resolve the reflection outcome gap before claiming training is going great."
                if reflection_says_not_improving
                else "Train MIM judgment mode selection until MIM-DURABILITY-SMOKE-V2 reaches at least 80%."
                if judgment_needs_attention
                else "Start daily/hourly scoreboard snapshots so tomorrow can compare against today with real deltas."
            ),
            "continue_condition": "Continue while blocker count, MIM communication score, or TOD validation evidence improves every 4-6 hours.",
            "redirect_condition": "Redirect if there is no new evidence artifact, no blocker movement, and no MIM eval improvement over a 6-hour window.",
        },
        "source_files": [
            str(TRAINING_ROOT / "MIM_TOD_HOURLY_REFLECTION.latest.json"),
            str(TRAINING_ROOT / "MIM_DURABILITY_SMOKE_V2.latest.json"),
            str(TRAINING_ROOT / "MIM_TOD_CONTINUOUS_TRAINING_DIRECTIVE.latest.json"),
            str(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_CLEARING_DRILL_002.latest.json"),
            str(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_003.latest.json"),
            str(BLOCKER_ROOT / "TOD_BLOCKER_RESOLUTION_DRILL_004.latest.json"),
            str(BLOCKER_ROOT / "TOD_BLOCKED_OBJECTIVE_TRIAGE.latest.json"),
        ],
    }
    return scoreboard


def metric_value(value: Any) -> str:
    if isinstance(value, dict):
        return "baseline needed"
    if value is None:
        return "baseline needed"
    return str(value)


def write_markdown(scoreboard: dict[str, Any], path: Path) -> None:
    mim = scoreboard["mim_score"]["metrics"]
    tod = scoreboard["tod_score"]["metrics"]
    hours = scoreboard["training_hours"]
    outcome = scoreboard.get("outcome_reflection") if isinstance(scoreboard.get("outcome_reflection"), dict) else {}
    judgment = scoreboard.get("judgment_mode_score") if isinstance(scoreboard.get("judgment_mode_score"), dict) else {}
    lines = [
        "# MIM/TOD Training Scoreboard",
        "",
        f"Generated: {scoreboard['generated_at']}",
        f"Status: {scoreboard['status']}",
        "",
        "## Outcome Reflection",
        "",
        f"- Reflection generated: {outcome.get('generated_at') or 'unknown'}",
        f"- Assessment: {outcome.get('assessment') or 'unknown'}",
        f"- Are outcomes improving: {outcome.get('are_they_improving')}",
        f"- Creating new objectives: {outcome.get('are_they_creating_new_objectives')}",
        f"- Truth integrity: {outcome.get('truth_integrity_status') or 'unknown'}",
        f"- Fresh artifacts: {metric_value(outcome.get('fresh_artifact_count'))}",
        f"- Stale artifacts: {metric_value(outcome.get('stale_artifact_count'))}",
        "",
        "Outcome summary:",
        "",
        f"> {outcome.get('operator_summary') or 'No hourly reflection summary available.'}",
        "",
        "Reflection recommendations:",
        "",
    ]
    recommendations = outcome.get("recommendations") if isinstance(outcome.get("recommendations"), list) else []
    if recommendations:
        for recommendation in recommendations[:5]:
            lines.append(f"- {recommendation}")
    else:
        lines.append("- No reflection recommendations available.")
    lines.extend([
        "",
        "## Training Hours",
        "",
        "| Window | Value | Status |",
        "|---|---:|---|",
    ])
    for label in ("last_7_days", "yesterday", "today"):
        item = hours[label]
        lines.append(f"| {label.replace('_', ' ').title()} | {metric_value(item.get('value'))} | {item.get('status')} |")
    lines.extend([
        "",
        "## MIM Score",
        "",
        "| Metric | Yesterday | Today | Source |",
        "|---|---:|---:|---|",
    ])
    for key, item in mim.items():
        lines.append(
            f"| {key.replace('_', ' ').title()} | {metric_value(item.get('yesterday'))} | {metric_value(item.get('today'))} | {item.get('source')} |"
        )
    lines.extend([
        "",
        "## MIM Judgment Mode Score",
        "",
        f"- Objective: {judgment.get('objective_id') or 'MIM-DURABILITY-SMOKE-V2'}",
        f"- Status: {judgment.get('status') or 'unknown'}",
        f"- Cases: {metric_value(judgment.get('case_count'))}",
        f"- Passed: {metric_value(judgment.get('passed'))}",
        f"- Failed: {metric_value(judgment.get('failed'))}",
        f"- Pass rate: {metric_value(judgment.get('pass_rate_percent'))}%",
        f"- Current weakness: {judgment.get('current_weakness') or 'unknown'}",
        f"- Target: {judgment.get('target') or 'unknown'}",
        "",
        "| Group | Passed | Failed |",
        "|---|---:|---:|",
    ])
    group_summary = (
        judgment.get("group_summary")
        if isinstance(judgment.get("group_summary"), dict)
        else {}
    )
    if group_summary:
        for group, values in sorted(group_summary.items()):
            group_values = values if isinstance(values, dict) else {}
            lines.append(
                f"| {group.replace('_', ' ').title()} | {metric_value(group_values.get('passed'))} | {metric_value(group_values.get('failed'))} |"
            )
    else:
        lines.append("| baseline needed | baseline needed | baseline needed |")
    lines.extend([
        "",
        "## TOD Score",
        "",
        "| Metric | Yesterday | Today | Source |",
        "|---|---:|---:|---|",
    ])
    for key, item in tod.items():
        today = item.get("today")
        lines.append(
            f"| {key.replace('_', ' ').title()} | {metric_value(item.get('yesterday'))} | {metric_value(today)} | {item.get('source')} |"
        )
    latest = scoreboard["tod_score"].get("latest_drill") or {}
    lines.extend([
        "",
        "## Latest Evidence",
        "",
        f"- Latest TOD drill: {latest.get('id')} ({latest.get('status')})",
        f"- Finding: {latest.get('finding')}",
        f"- Continue training: {scoreboard['recommendation']['continue_training']}",
        f"- Next required improvement: {scoreboard['recommendation']['next_required_improvement']}",
        "",
        "## Notes",
        "",
        "- Baseline-needed fields are not guessed. They become real numbers after scoreboard snapshots exist.",
        "- Internal jargon is a lower-is-better percentage from live MIM evaluation prompts.",
    ])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_snapshots(scoreboard: dict[str, Any], out_dir: Path) -> dict[str, str]:
    stamp = datetime.now(timezone.utc)
    compact_stamp = stamp.strftime("%Y%m%dT%H%M%SZ")
    day = stamp.strftime("%Y-%m-%d")
    snapshot_root = out_dir / "training_scoreboard_snapshots"
    hourly_dir = snapshot_root / "hourly"
    daily_dir = snapshot_root / "daily" / day
    hourly_dir.mkdir(parents=True, exist_ok=True)
    daily_dir.mkdir(parents=True, exist_ok=True)

    hourly_json = hourly_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.json"
    hourly_md = hourly_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.md"
    daily_json = daily_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.json"
    daily_md = daily_dir / f"MIM_TOD_TRAINING_SCOREBOARD.{compact_stamp}.md"
    for path in (hourly_json, daily_json):
        path.write_text(json.dumps(scoreboard, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for path in (hourly_md, daily_md):
        write_markdown(scoreboard, path)
    return {
        "hourly_json": str(hourly_json),
        "hourly_md": str(hourly_md),
        "daily_json": str(daily_json),
        "daily_md": str(daily_md),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="", help="Optional MIM base URL for live communication evaluation.")
    parser.add_argument("--operator-estimated-hours", type=float, default=None)
    parser.add_argument("--out-dir", default=str(TRAINING_ROOT))
    parser.add_argument("--write-snapshots", action="store_true")
    args = parser.parse_args()

    scoreboard = build_scoreboard(
        base_url=args.base_url.strip() or None,
        operator_estimated_hours=args.operator_estimated_hours,
    )
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "MIM_TOD_TRAINING_SCOREBOARD.latest.json"
    md_path = out_dir / "MIM_TOD_TRAINING_SCOREBOARD.latest.md"
    json_path.write_text(json.dumps(scoreboard, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(scoreboard, md_path)
    if args.write_snapshots:
        snapshots = write_snapshots(scoreboard, out_dir)
        scoreboard["snapshot_files"] = snapshots
        json_path.write_text(json.dumps(scoreboard, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        write_markdown(scoreboard, md_path)
    print(json_path)
    print(md_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
