from __future__ import annotations

import argparse
import json
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SUITE = ROOT / "tod" / "conversation_eval" / "mim_structural_reasoning_diversity_suite_v1.json"
DEFAULT_OUTPUT = ROOT / "runtime_remote_training" / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"
DEFAULT_MARKDOWN_OUTPUT = ROOT / "runtime_remote_training" / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.md"

INTERNAL_JARGON = (
    "mim-request-",
    "objective-",
    "task id",
    "request id",
    "dispatcher state",
    "tod_result_artifacts",
    "lifecycle",
)

PATTERNS = {
    "competing_interpretations": re.compile(
        r"\b(two|three|several|multiple|could mean|could be|possibilit|likely explanations|one of|conflicting evidence)\b",
        re.I,
    ),
    "evidence_boundary": re.compile(
        r"\b(evidence|prove|proof|validate|validation|source|known|unknown|confirm|verify|artifact|record|trace|screenshot|diff)\b",
        re.I,
    ),
    "uncertainty_tracking": re.compile(
        r"\b(assum|uncertain|not enough context|if you mean|until|unless|missing|unclear|I would not|cannot yet|not call|conflicting evidence)\b",
        re.I,
    ),
    "no_false_closure": re.compile(
        r"\b(not completed|not completion|not solved|keep .* open|blocked|block|do not declare|would not call|would not|not a pass|not progressing|before calling|until .* evidence)\b",
        re.I,
    ),
    "decision_diversity": re.compile(
        r"\b(option|path|first move|first step|start with|start by|instead|before|compare|compares|choose|recommend|smallest|audit|prototype|blueprint)\b",
        re.I,
    ),
    "action_without_overclaiming": re.compile(
        r"\b(owner|next action|first move|I would|should|start|inspect|map|trace|compare|audit|prototype|build brief|aging|Dave needed)\b",
        re.I,
    ),
}

FALSE_CLOSURE_MARKERS = re.compile(
    r"\b(done|completed|solved|fixed|successful|all set|approved)\b",
    re.I,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return value if isinstance(value, dict) else {}


def post_public_chat(base_url: str, session_key: str, prompt: str, timeout: int) -> str:
    payload = json.dumps(
        {"message": prompt, "mode": "mim", "session_key": session_key},
        ensure_ascii=False,
    ).encode("utf-8")
    request = urllib.request.Request(
        base_url.rstrip("/") + "/public/chat/message",
        data=payload,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "MIM structural reasoning smoke/1.0",
            "Accept": "application/json, text/plain, */*",
            "Origin": base_url.rstrip("/"),
            "Referer": base_url.rstrip("/") + "/",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.loads(response.read().decode("utf-8"))
    return str((data.get("reply") or {}).get("content") or "").strip()


def score_reply(prompt: str, reply: str) -> dict[str, Any]:
    return score_reply_for_dimensions(prompt, reply, tuple(PATTERNS))


def score_reply_for_dimensions(prompt: str, reply: str, required_dimensions: tuple[str, ...]) -> dict[str, Any]:
    normalized = " ".join(reply.split())
    lowered = normalized.lower()
    checks = {name: bool(pattern.search(normalized)) for name, pattern in PATTERNS.items()}
    jargon_hits = [marker for marker in INTERNAL_JARGON if marker in lowered]
    false_closure_hit = bool(FALSE_CLOSURE_MARKERS.search(normalized)) and not checks["evidence_boundary"]
    if not false_closure_hit and "no_false_closure" not in required_dimensions:
        checks["no_false_closure"] = True
    question_overload = normalized.count("?") > 3
    if false_closure_hit:
        checks["no_false_closure"] = False
    passed_count = sum(1 for passed in checks.values() if passed)
    score = round((passed_count / len(checks)) * 10, 1)
    failures = [name for name, passed in checks.items() if not passed]
    if jargon_hits:
        failures.append("internal_jargon_leakage")
        score = max(0.0, score - 1.5)
    if question_overload:
        failures.append("question_overload")
        score = max(0.0, score - 1.0)
    if false_closure_hit:
        failures.append("premature_closure_without_evidence")
    required_failures = [name for name in required_dimensions if not checks.get(name)]
    non_dimension_failures = [
        failure
        for failure in failures
        if failure in {"internal_jargon_leakage", "question_overload", "premature_closure_without_evidence"}
    ]
    passed = not required_failures and not non_dimension_failures and score >= 6.5
    return {
        "prompt": prompt,
        "reply": normalized,
        "reply_excerpt": normalized[:700],
        "checks": checks,
        "required_dimensions": list(required_dimensions),
        "required_failures": required_failures,
        "passed_dimensions": passed_count,
        "total_dimensions": len(checks),
        "score_10": score,
        "failures": failures,
        "passed": passed,
    }


def _load_replies(path: Path | None) -> dict[str, str]:
    if path is None:
        return {}
    payload = load_json(path)
    items = payload.get("replies") if isinstance(payload.get("replies"), list) else []
    replies: dict[str, str] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        scenario_id = str(item.get("scenario_id") or item.get("id") or "").strip()
        reply = str(item.get("reply") or "").strip()
        if scenario_id and reply:
            replies[scenario_id] = reply
    return replies


def build_scorecard(
    *,
    suite_path: Path,
    output_path: Path,
    markdown_path: Path | None,
    replies_path: Path | None,
    live_base_url: str | None,
    timeout: int,
    use_ideal: bool,
) -> dict[str, Any]:
    suite = load_json(suite_path)
    cards = [card for card in suite.get("scenario_cards", []) if isinstance(card, dict)]
    supplied_replies = _load_replies(replies_path)
    run_id = datetime.now(timezone.utc).strftime("mim-structural-%Y%m%dT%H%M%SZ")
    cases: list[dict[str, Any]] = []
    for index, card in enumerate(cards, start=1):
        scenario_id = str(card.get("id") or f"scenario-{index:03d}")
        prompt = str(card.get("prompt") or "")
        source = "ideal_reply_baseline"
        error = None
        if scenario_id in supplied_replies:
            reply = supplied_replies[scenario_id]
            source = str(replies_path)
        elif live_base_url:
            try:
                reply = post_public_chat(live_base_url, f"{run_id}-{index:03d}", prompt, timeout)
                source = live_base_url
            except (OSError, urllib.error.HTTPError, ValueError) as exc:
                reply = ""
                error = f"{type(exc).__name__}: {' '.join(str(exc).split())[:180]}"
                source = "live_error"
        elif use_ideal:
            reply = str(card.get("ideal_reply") or "")
        else:
            reply = ""
            error = "no_reply_source"
            source = "missing"
        required_dimensions = tuple(
            str(item)
            for item in (card.get("required_dimensions") if isinstance(card.get("required_dimensions"), list) else list(PATTERNS))
            if str(item) in PATTERNS
        )
        scored = score_reply_for_dimensions(prompt, reply, required_dimensions or tuple(PATTERNS))
        if error:
            scored["failures"] = sorted(set(scored["failures"] + ["reply_unavailable"]))
            scored["passed"] = False
            scored["error"] = error
        scored.update(
            {
                "scenario_id": scenario_id,
                "bucket": card.get("bucket"),
                "weight": float(card.get("weight") or 0.0),
                "source": source,
            }
        )
        cases.append(scored)

    total_weight = sum(float(case.get("weight") or 0.0) for case in cases)
    weighted_score = 0.0
    weighted_pass = 0.0
    for case in cases:
        weight = float(case.get("weight") or 0.0)
        weighted_score += weight * (float(case.get("score_10") or 0.0) / 10.0)
        weighted_pass += weight * (1.0 if case.get("passed") else 0.0)
    pass_count = sum(1 for case in cases if case.get("passed"))
    dimension_counts = {name: 0 for name in PATTERNS}
    for case in cases:
        checks = case.get("checks") if isinstance(case.get("checks"), dict) else {}
        for name in dimension_counts:
            if checks.get(name):
                dimension_counts[name] += 1
    metrics = [
        {
            "metric": name,
            "passed": count,
            "total": len(cases),
            "pass_rate": round(count / max(1, len(cases)), 4),
        }
        for name, count in dimension_counts.items()
    ]
    payload = {
        "packet_type": "mim-structural-reasoning-diversity-scorecard-v1",
        "objective_id": "MIM-STRUCTURAL-REASONING-DIVERSITY-V1",
        "generated_at": utc_now(),
        "suite_path": str(suite_path),
        "reply_source": "live" if live_base_url else ("provided_replies" if replies_path else "ideal_reply_baseline"),
        "status": "target_met" if total_weight and weighted_pass / total_weight >= 0.9 else "needs_training",
        "case_count": len(cases),
        "pass_count": pass_count,
        "pass_rate": round(pass_count / max(1, len(cases)), 4),
        "weighted_pass_rate": round(weighted_pass / total_weight, 4) if total_weight else 0.0,
        "weighted_structural_score": round((weighted_score / total_weight) * 10.0, 1) if total_weight else 0.0,
        "target_weighted_pass_rate": float(suite.get("target_pass_rate") or 0.9),
        "metrics": metrics,
        "cases": cases,
        "next_action": {
            "recommended_action": "Use failed dimensions as training pressure: require MIM to name competing interpretations, evidence boundaries, unresolved uncertainty, and one action before closure.",
            "owner": "MIM + TOD",
            "expected_evidence": "Fresh MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json with weighted pass >= 0.90 on live or exported replies.",
            "aging_rule": "Rerun after each customer-conversation prompt update or within 24h if weighted pass stays below target.",
            "dave_needed": "no",
        },
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    if markdown_path:
        markdown_path.parent.mkdir(parents=True, exist_ok=True)
        failures = [case for case in cases if not case.get("passed")]
        lines = [
            "# MIM Structural Reasoning Diversity Scorecard",
            "",
            f"Generated: {payload['generated_at']}",
            f"Status: {payload['status']}",
            f"Weighted pass rate: {payload['weighted_pass_rate']}",
            f"Weighted structural score: {payload['weighted_structural_score']}/10",
            f"Cases: {payload['pass_count']}/{payload['case_count']} passed",
            "",
            "## Dimension Coverage",
            "",
        ]
        for row in metrics:
            lines.append(f"- {row['metric']}: {row['passed']}/{row['total']} ({row['pass_rate']})")
        lines.extend(["", "## Failed Cases"])
        if failures:
            for case in failures[:20]:
                lines.append(f"- {case['scenario_id']}: {', '.join(case.get('failures') or [])}")
        else:
            lines.append("- none")
        lines.extend(
            [
                "",
                "## Next Action",
                "",
                f"- {payload['next_action']['recommended_action']}",
            ]
        )
        markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--markdown-output", default=str(DEFAULT_MARKDOWN_OUTPUT))
    parser.add_argument("--replies", default=None, help="Optional JSON with replies: [{scenario_id, reply}].")
    parser.add_argument("--live-base-url", default=None, help="Optional mimtod public-chat base URL.")
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--no-ideal-baseline", action="store_true")
    args = parser.parse_args()
    payload = build_scorecard(
        suite_path=Path(args.suite),
        output_path=Path(args.output),
        markdown_path=Path(args.markdown_output) if args.markdown_output else None,
        replies_path=Path(args.replies) if args.replies else None,
        live_base_url=args.live_base_url,
        timeout=args.timeout,
        use_ideal=not args.no_ideal_baseline,
    )
    print(
        json.dumps(
            {
                "status": payload["status"],
                "case_count": payload["case_count"],
                "weighted_pass_rate": payload["weighted_pass_rate"],
                "weighted_structural_score": payload["weighted_structural_score"],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
