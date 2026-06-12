from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from core.config import PROJECT_ROOT


SMOKE_ARTIFACTS = {
    "universal": "universal_mim_customer_conversation_smoke.latest.json",
    "public_customer": "public_mim_customer_conversation_smoke.latest.json",
    "public_general": "public_mim_general_conversation_smoke.latest.json",
}


FAILURE_FAMILIES = {
    "direct_answer": {
        "unnecessary_clarification",
        "old_france_clarifier",
        "lost_location_followup",
        "lost_followup_context",
    },
    "language": {"language_mismatch_spanish"},
    "internal_jargon": {
        "internal_jargon_leakage",
        "operator_contract_leak",
        "lifecycle_leakage",
        "human_chat_internal_jargon",
    },
    "build_request": {"missing_build_path", "build_discovery_overload"},
    "business_problem": {"missing_root_problem_frame"},
    "conversion": {"conversion_next_step_missing", "conversion_too_vague"},
    "troubleshooting": {"troubleshooting_next_action_missing"},
    "project_management": {"pm_recommendation_missing"},
    "demonstration": {"demo_path_missing"},
    "latency_or_availability": {"request_error", "auth_required", "bootstrap_error", "login_error"},
    "conversation_shape": {"too_many_questions", "overlong_public_reply", "consultant_mode_failed"},
}


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _candidate_eval_roots(project_root: Path = PROJECT_ROOT) -> list[Path]:
    roots = [
        project_root / "runtime" / "shared" / "conversation_eval",
        project_root / "shared_state" / "conversation_eval",
        project_root.parent / "shared_state" / "conversation_eval",
    ]
    unique: list[Path] = []
    for root in roots:
        if root not in unique:
            unique.append(root)
    return unique


def _read_json(path: Path) -> dict[str, Any] | None:
    try:
        if not path.exists():
            return None
        payload = json.loads(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else None
    except Exception:
        return None


def _find_artifact(filename: str, roots: list[Path]) -> tuple[Path | None, dict[str, Any] | None]:
    for root in roots:
        path = root / filename
        payload = _read_json(path)
        if payload is not None:
            return path, payload
    return None, None


def _failure_family(tag: str) -> str:
    clean = str(tag or "").strip()
    for family, tags in FAILURE_FAMILIES.items():
        if clean in tags or any(clean.startswith(prefix) for prefix in tags):
            return family
    return "other"


def _artifact_age_seconds(path: Path | None) -> int | None:
    if path is None or not path.exists():
        return None
    try:
        return max(0, int(datetime.now(timezone.utc).timestamp() - path.stat().st_mtime))
    except Exception:
        return None


def _surface_summary(report: dict[str, Any]) -> list[dict[str, Any]]:
    surfaces = report.get("surfaces")
    if isinstance(surfaces, list):
        output = []
        for surface in surfaces:
            if not isinstance(surface, dict):
                continue
            summary = surface.get("summary") if isinstance(surface.get("summary"), dict) else {}
            output.append(
                {
                    "surface": surface.get("surface") or "unknown",
                    "available": bool(surface.get("available")),
                    "unavailable_reason": surface.get("unavailable_reason") or "",
                    "scenario_count": summary.get("scenario_count") or 0,
                    "passed_count": summary.get("passed_count") or 0,
                    "failure_count": summary.get("failure_count") or 0,
                    "weighted_pass_rate": summary.get("weighted_pass_rate"),
                    "pass_rate": summary.get("pass_rate"),
                }
            )
        return output
    summary = report.get("summary") if isinstance(report.get("summary"), dict) else {}
    return [
        {
            "surface": "mimtod_public_chat",
            "available": True,
            "unavailable_reason": "",
            "scenario_count": summary.get("scenario_count") or 0,
            "passed_count": summary.get("passed_count") or 0,
            "failure_count": summary.get("failure_count") or 0,
            "weighted_pass_rate": summary.get("weighted_pass_rate"),
            "pass_rate": summary.get("pass_rate"),
        }
    ]


def _iter_runs(report: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    surfaces = report.get("surfaces")
    if isinstance(surfaces, list):
        pairs: list[tuple[str, dict[str, Any]]] = []
        for surface in surfaces:
            if not isinstance(surface, dict):
                continue
            surface_name = str(surface.get("surface") or "unknown")
            for run in surface.get("runs") or []:
                if isinstance(run, dict):
                    pairs.append((surface_name, run))
        return pairs
    pairs = []
    for run in report.get("runs") or []:
        if isinstance(run, dict):
            pairs.append(("mimtod_public_chat", run))
    return pairs


def _analyze_failures(reports: dict[str, dict[str, Any]]) -> dict[str, Any]:
    tag_counts: Counter[str] = Counter()
    family_counts: Counter[str] = Counter()
    surface_counts: Counter[str] = Counter()
    category_counts: Counter[str] = Counter()
    examples: list[dict[str, Any]] = []
    for report_name, report in reports.items():
        for surface, run in _iter_runs(report):
            failures = [str(item) for item in (run.get("failures") or []) if item]
            if not failures:
                continue
            bucket = str(run.get("bucket") or "unknown")
            surface_counts[surface] += 1
            category_counts[bucket] += 1
            for tag in failures:
                tag_counts[tag] += 1
                family_counts[_failure_family(tag)] += 1
            if len(examples) < 12:
                first_turn = (run.get("turns") or [{}])[0] if isinstance(run.get("turns"), list) else {}
                examples.append(
                    {
                        "report": report_name,
                        "surface": surface,
                        "scenario_id": run.get("scenario_id") or "",
                        "bucket": bucket,
                        "failures": failures,
                        "turn": first_turn.get("turn") or "",
                        "reply_excerpt": str(first_turn.get("reply") or "")[:320],
                    }
                )
    return {
        "tag_counts": [{"tag": tag, "count": count} for tag, count in tag_counts.most_common(20)],
        "family_counts": [{"family": tag, "count": count} for tag, count in family_counts.most_common(12)],
        "surface_failure_counts": [{"surface": tag, "count": count} for tag, count in surface_counts.most_common(12)],
        "category_failure_counts": [{"category": tag, "count": count} for tag, count in category_counts.most_common(12)],
        "examples": examples,
    }


def _next_actions(quality: dict[str, Any]) -> list[dict[str, str]]:
    failures = {row["family"]: int(row["count"]) for row in quality.get("failure_analysis", {}).get("family_counts", [])}
    unavailable = []
    for artifact in quality.get("artifacts", []):
        for surface in artifact.get("surfaces") or []:
            if not surface.get("available"):
                unavailable.append(surface)
    actions: list[dict[str, str]] = []
    if unavailable:
        actions.append(
            {
                "priority": "high",
                "action": "Authorize and run logged-in AgentMIM surface certification.",
                "owner": "Codex/MIM",
                "evidence": "Universal smoke has no auth_required surfaces and reports all five surfaces.",
            }
        )
    if failures.get("latency_or_availability", 0):
        actions.append(
            {
                "priority": "high",
                "action": "Treat timeout/HTTP failures as customer-facing outages before tuning language.",
                "owner": "MIM/TOD",
                "evidence": "Request-error family count returns to zero in the next universal smoke.",
            }
        )
    if failures.get("conversion", 0) or failures.get("build_request", 0):
        actions.append(
            {
                "priority": "high",
                "action": "Repair first-reply conversion and build-request examples, then add each as a regression card.",
                "owner": "MIM",
                "evidence": "Build and conversion categories pass at or above 95% weighted coverage.",
            }
        )
    if failures.get("internal_jargon", 0):
        actions.append(
            {
                "priority": "critical",
                "action": "Block internal lifecycle/artifact language from customer surfaces.",
                "owner": "MIM",
                "evidence": "Internal jargon leakage count is zero across all public and AgentMIM surfaces.",
            }
        )
    if not actions:
        actions.append(
            {
                "priority": "normal",
                "action": "Keep the rolling 50-100 scenario daily smoke active and sample real visitor conversations weekly.",
                "owner": "MIM/TOD",
                "evidence": "Dashboard remains above 95% weighted pass with zero jargon leakage.",
            }
        )
    return actions[:6]


def build_interaction_quality_snapshot(project_root: Path = PROJECT_ROOT) -> dict[str, Any]:
    roots = _candidate_eval_roots(project_root)
    artifacts: list[dict[str, Any]] = []
    loaded_reports: dict[str, dict[str, Any]] = {}
    for key, filename in SMOKE_ARTIFACTS.items():
        path, payload = _find_artifact(filename, roots)
        if payload is None:
            artifacts.append(
                {
                    "key": key,
                    "available": False,
                    "filename": filename,
                    "path": "",
                    "generated_at": "",
                    "age_seconds": None,
                    "surfaces": [],
                }
            )
            continue
        loaded_reports[key] = payload
        rollup = payload.get("rollup") if isinstance(payload.get("rollup"), dict) else {}
        summary = payload.get("summary") if isinstance(payload.get("summary"), dict) else {}
        artifacts.append(
            {
                "key": key,
                "available": True,
                "filename": filename,
                "path": str(path) if path else "",
                "generated_at": payload.get("generated_at") or summary.get("generated_at") or "",
                "age_seconds": _artifact_age_seconds(path),
                "scenario_count": payload.get("scenario_count_per_surface") or summary.get("scenario_count") or 0,
                "weighted_pass_rate": rollup.get("weighted_pass_rate", summary.get("weighted_pass_rate")),
                "pass_rate": summary.get("pass_rate"),
                "internal_jargon_failure_count": rollup.get("internal_jargon_failure_count", 0),
                "passes_threshold": rollup.get("passes_threshold"),
                "surfaces": _surface_summary(payload),
            }
        )
    failure_analysis = _analyze_failures(loaded_reports)
    best_weighted = [
        item.get("weighted_pass_rate")
        for item in artifacts
        if isinstance(item.get("weighted_pass_rate"), (int, float))
    ]
    quality = {
        "schema_version": "mim-interaction-quality-dashboard-v1",
        "generated_at": _now_iso(),
        "artifact_roots": [str(root) for root in roots],
        "artifacts": artifacts,
        "failure_analysis": failure_analysis,
        "headline": {
            "available_artifacts": sum(1 for item in artifacts if item.get("available")),
            "best_weighted_pass_rate": max(best_weighted) if best_weighted else None,
            "total_failure_examples": len(failure_analysis.get("examples") or []),
            "internal_jargon_failure_count": sum(
                int(item.get("internal_jargon_failure_count") or 0) for item in artifacts
            ),
        },
    }
    quality["next_actions"] = _next_actions(quality)
    return quality
