#!/usr/bin/env python3
"""Build the organizational maintenance scorecard.

This scorecard measures the MIM/TOD operating model after the architecture moved
from isolated behavior tests toward organizational competence. It intentionally
marks uninstrumented metrics as instrumentation_required instead of inventing
scores.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"
READ_ONLY_ARTIFACT_ROOT = TRAINING_ROOT / "read_only_audit_artifacts"
REGISTRY_PATH = ROOT / "docs" / "training" / "TOD_APPRENTICESHIP_REGISTRY.md"
OUTPUT_JSON = TRAINING_ROOT / "MIM_TOD_ORGANIZATIONAL_MAINTENANCE_SCORECARD.latest.json"
OUTPUT_MD = TRAINING_ROOT / "MIM_TOD_ORGANIZATIONAL_MAINTENANCE_SCORECARD.latest.md"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def status_from_ratio(value: float | None, target: float, *, higher_is_better: bool = True) -> str:
    if value is None:
        return "instrumentation_required"
    if higher_is_better:
        return "passed" if value >= target else "needs_repair"
    return "passed" if value <= target else "needs_repair"


def parse_apprenticeship_registry(text: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    matches = list(re.finditer(r"^###\s+(APP-TOD-\d+):\s*(.+)$", text, flags=re.MULTILINE))
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[start:end]
        progress = _first_backtick_field(body, "Progress") or "unknown"
        proficiency = _first_backtick_field(body, "Proficiency") or "unknown"
        retirement_line = _first_plain_field(body, "Retirement") or "unknown"
        entries.append(
            {
                "id": match.group(1),
                "name": match.group(2).strip(),
                "progress": progress,
                "proficiency": proficiency,
                "retirement": retirement_line,
            }
        )
    return entries


def _first_backtick_field(body: str, label: str) -> str | None:
    match = re.search(rf"^{re.escape(label)}:\s*`([^`]+)`", body, flags=re.MULTILINE)
    if match:
        return match.group(1).strip()
    return None


def _first_plain_field(body: str, label: str) -> str | None:
    match = re.search(rf"^{re.escape(label)}:\s*(.+)$", body, flags=re.MULTILINE)
    if match:
        return match.group(1).strip()
    return None


def borrowed_capability_ratio(entries: list[dict[str, Any]], previous: dict[str, Any] | None = None) -> dict[str, Any]:
    borrowed_states = {"borrowed", "assimilating", "scaffolded_pass", "independent_demo_pending", "unknown"}
    independent_states = {"independent_demo_passed", "frozen", "retired"}
    retired_states = {"retired"}

    borrowed_count = 0
    independent_count = 0
    retired_count = 0
    unknown_count = 0
    for entry in entries:
        progress = str(entry.get("progress") or "unknown").strip()
        if progress in retired_states:
            retired_count += 1
        if progress in independent_states:
            independent_count += 1
        elif progress in borrowed_states:
            borrowed_count += 1
        else:
            unknown_count += 1
            borrowed_count += 1

    total = len(entries)
    borrowed_percent = round((borrowed_count / total) * 100, 1) if total else 0.0
    independent_percent = round((independent_count / total) * 100, 1) if total else 0.0
    current = {
        "total_entries": total,
        "borrowed_count": borrowed_count,
        "independent_count": independent_count,
        "retired_count": retired_count,
        "unknown_count": unknown_count,
        "borrowed_percent": borrowed_percent,
        "independent_percent": independent_percent,
    }
    previous_current = previous.get("current") if isinstance(previous, dict) else None
    trend = "baseline"
    if isinstance(previous_current, dict):
        prev_borrowed = previous_current.get("borrowed_percent")
        if isinstance(prev_borrowed, (int, float)):
            if borrowed_percent < float(prev_borrowed):
                trend = "improving"
            elif borrowed_percent > float(prev_borrowed):
                trend = "regressing"
            else:
                trend = "flat"
    return {"current": current, "previous": previous_current, "trend": trend}


def metric(name: str, status: str, current: str, target: str, source: str, next_action: str) -> dict[str, str]:
    return {
        "metric": name,
        "status": status,
        "current": current,
        "target": target,
        "source": source,
        "next_action": next_action,
    }


def build_scorecard() -> dict[str, Any]:
    prior = load_json(OUTPUT_JSON)
    operator = load_json(TRAINING_ROOT / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json")
    context = load_json(TRAINING_ROOT / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json")
    movement = load_json(TRAINING_ROOT / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json")
    ladder = load_json(TRAINING_ROOT / "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_SCORECARD.latest.json")
    auditor_cert = load_json(READ_ONLY_ARTIFACT_ROOT / "STUDIO_AUDITOR_OBSERVATORY_CERTIFICATION_V1.latest.json")
    registry_text = REGISTRY_PATH.read_text(encoding="utf-8") if REGISTRY_PATH.exists() else ""
    registry_entries = parse_apprenticeship_registry(registry_text)
    borrowed_ratio = borrowed_capability_ratio(registry_entries, prior.get("borrowed_capability_ratio") if prior else None)

    operator_score = operator.get("operator_impact_score")
    context_rate = context.get("weighted_pass_rate")
    auditor_passed = auditor_cert.get("passed_count")
    auditor_total = auditor_cert.get("total_count")
    strict_current = ladder.get("strict_independent_resolution_count")
    strict_target = ladder.get("strict_independent_resolution_target")
    broader_independent = _metric_current(movement, "Independent TOD Resolutions")
    validated_edits = _metric_current(movement, "Validated TOD Edits")
    meaningful_impl = _metric_current(movement, "Meaningful TOD Implementations")
    selector_state = _metric_current(movement, "TOD Selector Field Completeness")
    material_state = _metric_current(movement, "TOD Material Execution State")

    mim_metrics = [
        metric(
            "Executive Recommendation Quality",
            status_from_ratio(_as_float(operator_score), 8.0),
            f"{operator_score}/10" if operator_score is not None else "not measured",
            "8/10+",
            "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
            "Bind recommendations to outcomes and rerun the live-10 operator-impact score.",
        ),
        metric(
            "Conversation Act Recognition",
            "instrumentation_required",
            "not separately scored",
            "90%+ across objective, coaching, correction, brainstorming, decision, observation, review, approval, rejection, information sharing, and question acts",
            "new metric contract",
            "Add an auditor suite that scores communication act before purpose, mode, or authority selection.",
        ),
        metric(
            "Objective Stewardship",
            "instrumentation_required",
            "not separately scored",
            "active objective persists across turns until completed, paused, split, or archived",
            "new metric contract",
            "Score objective assignment, acceptance, progress reporting, and closure continuity.",
        ),
        metric(
            "Coaching Assimilation",
            "instrumentation_required",
            "not separately scored",
            "coaching changes future behavior without route patches",
            "new metric contract",
            "Track coaching input -> learned rule -> future unseen prompt behavior.",
        ),
        metric(
            "Reflection Quality",
            "instrumentation_required",
            "not separately scored",
            "reflection names what changed, what was wrong, and next learning proof",
            "new metric contract",
            "Add a reflection rubric with evidence links and future behavior check.",
        ),
        metric(
            "Product Mastery",
            "partial",
            _auditor_cert_summary(auditor_passed, auditor_total),
            "10/10 core service questions plus audience-specific explanations",
            "STUDIO_AUDITOR_OBSERVATORY_CERTIFICATION_V1.latest.json",
            "Extend beyond Observatory certification into Enterprise and AgentMIM product suites.",
        ),
        metric(
            "Audience Adaptation",
            "instrumentation_required",
            "not separately scored",
            "CEO, administrator, broker, customer, and technical operator answers differ appropriately",
            "new metric contract",
            "Create audience-variant prompts and fail generic reused answers.",
        ),
        metric(
            "Referential Continuity",
            status_from_ratio(_as_float(context_rate), 0.90),
            f"{round(float(context_rate) * 100, 1)}% weighted pass" if isinstance(context_rate, (int, float)) else "not measured",
            "90%+",
            "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json",
            "Keep scoring prior-turn, page, upload, project, and evidence-boundary context.",
        ),
        metric(
            "Active Objective Continuity",
            "instrumentation_required",
            "not separately scored",
            "follow-up status questions answer against the active objective",
            "new metric contract",
            "Create active-objective continuity smoke with objective assignment plus follow-up checks.",
        ),
        metric(
            "Evidence Source Selection",
            "instrumentation_required",
            "not separately scored",
            "MIM chooses current evidence before claims or static templates",
            "new metric contract",
            "Score source selection across live artifacts, DB/page context, uploaded files, and research evidence.",
        ),
    ]

    tod_metrics = [
        metric(
            "Independent Execution",
            "level_0_in_progress",
            f"{strict_current}/{strict_target} strict proofs; {broader_independent} broader independent resolutions",
            "5/5 strict level-0 proofs before next complexity level",
            "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_SCORECARD.latest.json",
            "Complete one more strict level-0 independent proof without Codex-supplied patch content.",
        ),
        metric(
            "Recovery Quality",
            "needs_repair",
            material_state,
            "blocked diagnosis becomes a corrected executable retry shape",
            "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json",
            "Train recovery to produce missing requirement, corrected mode, retry payload, validation command, and expected evidence.",
        ),
        metric(
            "Evidence Integrity",
            "improving",
            f"{validated_edits} validated edits; wrapper-only completion rejected when material proof is missing",
            "no wrapper-only completion credited",
            "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json",
            "Keep requiring changed files or meaningful artifact write plus validation evidence.",
        ),
        metric(
            "Blocker Honesty",
            "improving",
            "latest execution truth reports blocked instead of false success",
            "blocked work names exact blocker and owner",
            "runtime/shared/TOD_EXECUTION_RESULT.latest.json",
            "Resolve status-truth conflicts so blocker honesty is also visible in the live lane.",
        ),
        metric(
            "Replan Quality",
            "needs_repair",
            "recovery can still stop at blocked/status without a new executable shape",
            "every failed attempt creates a smaller valid retry or explicit external dependency",
            "TOD_CAPABILITY_ASSESSMENT_V1.latest.json",
            "Train one recovery drill where TOD transforms a blocker into a valid retry packet.",
        ),
        metric(
            "Bounded Slice Selection",
            "needs_repair",
            selector_state,
            "8/8 bounded selector fields before dispatch",
            "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json",
            "Require selected_task_id, target_file, target rule, behavior delta, validation command, expected changed files, rollback note, and prevention lesson.",
        ),
        metric(
            "Execution Ownership",
            "emerging",
            f"{meaningful_impl} meaningful implementations; strict ladder still {strict_current}/{strict_target}",
            "TOD owns inspect -> change -> validate -> evidence loop",
            "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json",
            "Advance only with fresh strict proofs that do not rely on Codex patch authorship.",
        ),
        metric(
            "Borrowed Capability Reduction",
            "baseline" if borrowed_ratio["trend"] == "baseline" else ("improving" if borrowed_ratio["trend"] == "improving" else "needs_repair"),
            f"{borrowed_ratio['current']['borrowed_percent']}% borrowed / {borrowed_ratio['current']['independent_percent']}% independent",
            "borrowed percent decreases month over month",
            "TOD_APPRENTICESHIP_REGISTRY.md",
            "Retire one borrowed capability only after fresh independent demonstration and freeze.",
        ),
        metric(
            "Autonomous Recovery Rate",
            "instrumentation_required",
            "not separately scored",
            "internal blockers resolved by TOD before Codex intervention",
            "new metric contract",
            "Track blocker -> TOD diagnosis -> TOD repair -> validation -> resumed objective without Codex patching.",
        ),
    ]

    return {
        "artifact_type": "mim_tod_organizational_maintenance_scorecard_v1",
        "generated_at": utc_now(),
        "objective_id": "TOD-ORGANIZATIONAL-MAINTENANCE-CYCLE-V1",
        "status": "active_measurement_contract_established",
        "codex_role": "advisory_and_validation_only",
        "borrowed_capability_ratio": borrowed_ratio,
        "mim_scorecard": {
            "status": _section_status(mim_metrics),
            "metrics": mim_metrics,
        },
        "tod_scorecard": {
            "status": _section_status(tod_metrics),
            "metrics": tod_metrics,
        },
        "auditor_update": {
            "status": "planned_not_complete",
            "required_questions": [
                "Can I trust the system?",
                "What is actually true?",
                "What is MIM claiming?",
                "Why should I believe it?",
            ],
            "next_objective": "STUDIO-AUDITOR-OPERATIONAL-TRUTH-CENTER-V1",
        },
        "enterprise_review": {
            "status": "roadmap_review_required",
            "focus": "Enterprise product mastery and first-login onboarding through branded tenant home.",
        },
        "agentmim_review": {
            "status": "roadmap_review_required",
            "focus": "Images, commissions, customer workflows, quote workbooks, reports, and MIM side-assistant timeouts.",
        },
        "organizational_constitution": {
            "status": "drafted",
            "path": "docs/training/MIM_TOD_ORGANIZATIONAL_CONSTITUTION_V1.md",
        },
        "next_action": "TOD should execute the first measured maintenance slice: add instrumentation for Conversation Act Recognition without adding hardcoded response routes.",
    }


def _metric_current(scorecard: dict[str, Any], metric_name: str) -> str:
    for item in scorecard.get("metrics") or []:
        if isinstance(item, dict) and item.get("metric") == metric_name:
            return str(item.get("current", "unknown"))
    return "unknown"


def _as_float(value: Any) -> float | None:
    try:
        if value is None or value == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _auditor_cert_summary(passed: Any, total: Any) -> str:
    if isinstance(passed, int) and isinstance(total, int) and total:
        return f"{passed}/{total} Observatory service certification"
    return "certification artifact present; count unavailable"


def _section_status(metrics: list[dict[str, str]]) -> str:
    statuses = {metric["status"] for metric in metrics}
    if "needs_repair" in statuses:
        return "needs_repair"
    if "instrumentation_required" in statuses:
        return "instrumentation_required"
    if "partial" in statuses:
        return "partial"
    return "passed"


def write_outputs(scorecard: dict[str, Any]) -> None:
    TRAINING_ROOT.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(json.dumps(scorecard, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# MIM/TOD Organizational Maintenance Scorecard",
        "",
        f"Generated: {scorecard['generated_at']}",
        f"Status: `{scorecard['status']}`",
        "",
        "## Borrowed Capability Ratio",
        "",
        f"- Borrowed: {scorecard['borrowed_capability_ratio']['current']['borrowed_percent']}%",
        f"- Independent: {scorecard['borrowed_capability_ratio']['current']['independent_percent']}%",
        f"- Trend: {scorecard['borrowed_capability_ratio']['trend']}",
        "",
        "## MIM Metrics",
        "",
    ]
    lines.extend(_metric_table(scorecard["mim_scorecard"]["metrics"]))
    lines.extend(["", "## TOD Metrics", ""])
    lines.extend(_metric_table(scorecard["tod_scorecard"]["metrics"]))
    lines.extend(
        [
            "",
            "## Next Action",
            "",
            scorecard["next_action"],
            "",
        ]
    )
    OUTPUT_MD.write_text("\n".join(lines), encoding="utf-8")


def _metric_table(metrics: list[dict[str, str]]) -> list[str]:
    lines = ["| Metric | Status | Current | Target |", "| --- | --- | --- | --- |"]
    for item in metrics:
        lines.append(
            "| {metric} | `{status}` | {current} | {target} |".format(
                metric=_escape_md(item["metric"]),
                status=_escape_md(item["status"]),
                current=_escape_md(item["current"]),
                target=_escape_md(item["target"]),
            )
        )
    return lines


def _escape_md(value: str) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def main() -> int:
    scorecard = build_scorecard()
    write_outputs(scorecard)
    print(f"wrote {OUTPUT_JSON.relative_to(ROOT)}")
    print(f"wrote {OUTPUT_MD.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
