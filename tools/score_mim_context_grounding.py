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
DEFAULT_SUITE = ROOT / "tod" / "conversation_eval" / "mim_context_grounding_suite_v1.json"
DEFAULT_OUTPUT = ROOT / "runtime_remote_training" / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"
DEFAULT_MARKDOWN_OUTPUT = ROOT / "runtime_remote_training" / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.md"

INTERNAL_JARGON = (
    "mim-request-",
    "objective id",
    "objective:",
    "artifact id",
    "dispatcher state",
    "tod_result_artifacts",
    "lifecycle",
)

STATIC_TRAINING_DUMPS = (
    "category smoke test",
    "category 1",
    "success:",
    "failure:",
    "weighted pass",
    "scorecard reports",
    "acceptance:",
)

LAZY_CLARIFIERS = (
    "could you clarify what specific topic or context",
    "can you clarify what you mean",
    "please clarify your request",
    "what specific topic are you asking about",
)

EVIDENCE_TERMS = re.compile(
    r"\b(evidence|prove|proof|validate|validation|verify|source|record|trace|report|before/after|compare|reconcile|audit|current|known|unknown|not enough context)\b",
    re.I,
)

ACTION_TERMS = re.compile(
    r"\b(next|first|start|apply|audit|compare|reconcile|route|show|answer|look up|inspect|update|stage|recommend|should)\b",
    re.I,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def normalize(text: str) -> str:
    return " ".join(str(text or "").split())


def contains_any(text: str, terms: list[str]) -> bool:
    lowered = text.lower()
    return any(str(term).lower() in lowered for term in terms)


def load_replies(path: Path | None) -> dict[str, str]:
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


def post_public_chat(base_url: str, session_key: str, turns: list[str], timeout: int) -> str:
    reply = ""
    for turn in turns:
        payload = json.dumps(
            {"message": turn, "mode": "mim", "session_key": session_key},
            ensure_ascii=False,
        ).encode("utf-8")
        request = urllib.request.Request(
            base_url.rstrip("/") + "/public/chat/message",
            data=payload,
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "User-Agent": "MIM context grounding smoke/1.0",
                "Accept": "application/json, text/plain, */*",
                "Origin": base_url.rstrip("/"),
                "Referer": base_url.rstrip("/") + "/",
            },
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = json.loads(response.read().decode("utf-8"))
        reply = str((data.get("reply") or {}).get("content") or "").strip()
    return reply


def score_case(card: dict[str, Any], reply: str, source: str, error: str | None = None) -> dict[str, Any]:
    text = normalize(reply)
    lowered = text.lower()
    turns = [str(turn) for turn in card.get("turns") or []]
    prompt_text = " ".join(turns).lower()
    failures: list[str] = []
    checks: dict[str, bool] = {}

    required_groups = [
        [str(term) for term in group]
        for group in (card.get("required_terms_any") if isinstance(card.get("required_terms_any"), list) else [])
        if isinstance(group, list)
    ]
    required_hits = [contains_any(text, group) for group in required_groups]
    checks["context_reference"] = all(required_hits) if required_hits else bool(text)
    if not checks["context_reference"]:
        failures.append("missing_required_context_reference")

    forbidden_terms = [
        str(term)
        for term in (card.get("forbidden_terms") if isinstance(card.get("forbidden_terms"), list) else [])
    ]
    forbidden_hits = [
        term
        for term in forbidden_terms
        if term and term.lower() in lowered
    ]
    if forbidden_hits:
        failures.append("forbidden_context_or_canned_phrase")

    internal_hits = [term for term in INTERNAL_JARGON if term in lowered]
    checks["no_internal_jargon"] = not internal_hits
    if internal_hits:
        failures.append("internal_jargon_leakage")

    static_hits = [term for term in STATIC_TRAINING_DUMPS if term in lowered]
    checks["no_canned_dump"] = not static_hits and len(text.split()) <= 230
    if static_hits:
        failures.append("static_training_dump")
    if len(text.split()) > 230:
        failures.append("overlong_context_dump")

    lazy_hits = [term for term in LAZY_CLARIFIERS if term in lowered]
    checks["no_lazy_clarification"] = not lazy_hits
    if lazy_hits:
        failures.append("lazy_clarification")

    checks["evidence_boundary"] = bool(EVIDENCE_TERMS.search(text))
    if not checks["evidence_boundary"] and any(
        source_key in (card.get("context_sources") or [])
        for source_key in ("page_context", "upload_context", "project_context_if_available", "provider_config", "current_chat_dialog")
    ):
        failures.append("missing_evidence_boundary")

    checks["direct_question_answered"] = checks["context_reference"] or bool(ACTION_TERMS.search(text)) or not any(
        token in prompt_text for token in ("what", "why", "can you", "which", "where", "apply", "build")
    )
    if not checks["direct_question_answered"]:
        failures.append("direct_question_not_answered")

    checks["prior_turn_continuity"] = True
    if len(turns) > 1 or "prior_turn" in (card.get("context_sources") or []):
        checks["prior_turn_continuity"] = not any(term in lowered for term in LAZY_CLARIFIERS)
        if not checks["prior_turn_continuity"]:
            failures.append("lost_prior_turn_context")

    checks["page_surface_grounding"] = True
    if card.get("page_context"):
        checks["page_surface_grounding"] = checks["context_reference"] and not any(
            phrase in lowered for phrase in ("i do not have access to the page", "i can't see the page")
        )
        if not checks["page_surface_grounding"]:
            failures.append("page_surface_context_not_used")

    if error:
        failures.append("reply_unavailable")

    passed_dimensions = sum(1 for passed in checks.values() if passed)
    score_10 = round((passed_dimensions / max(1, len(checks))) * 10.0, 1)
    passed = not failures and score_10 >= 8.0
    return {
        "scenario_id": card.get("id"),
        "bucket": card.get("bucket"),
        "surface": card.get("surface"),
        "weight": float(card.get("weight") or 0.0),
        "context_sources": card.get("context_sources") if isinstance(card.get("context_sources"), list) else [],
        "reply_source": source,
        "reply_excerpt": text[:900],
        "checks": checks,
        "required_context_group_hits": required_hits,
        "forbidden_hits": forbidden_hits,
        "score_10": score_10,
        "failures": sorted(set(failures)),
        "passed": passed,
        **({"error": error} if error else {}),
    }


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
    supplied_replies = load_replies(replies_path)
    run_id = datetime.now(timezone.utc).strftime("mim-context-grounding-%Y%m%dT%H%M%SZ")
    cases: list[dict[str, Any]] = []
    for index, card in enumerate(cards, start=1):
        scenario_id = str(card.get("id") or f"context-{index:03d}")
        turns = [str(turn) for turn in card.get("turns") or []]
        source = "ideal_reply_baseline"
        error = None
        if scenario_id in supplied_replies:
            reply = supplied_replies[scenario_id]
            source = str(replies_path)
        elif live_base_url and card.get("surface") == "public_chat":
            try:
                reply = post_public_chat(live_base_url, f"{run_id}-{index:03d}", turns, timeout)
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
        cases.append(score_case(card, reply, source, error))

    total_weight = sum(float(case.get("weight") or 0.0) for case in cases)
    weighted_pass = sum(float(case.get("weight") or 0.0) for case in cases if case.get("passed"))
    weighted_score = sum(float(case.get("weight") or 0.0) * (float(case.get("score_10") or 0.0) / 10.0) for case in cases)
    pass_count = sum(1 for case in cases if case.get("passed"))
    dimension_names = sorted({name for case in cases for name in (case.get("checks") or {})})
    metrics = []
    for name in dimension_names:
        passed_count = sum(1 for case in cases if (case.get("checks") or {}).get(name))
        metrics.append(
            {
                "metric": name,
                "passed": passed_count,
                "total": len(cases),
                "pass_rate": round(passed_count / max(1, len(cases)), 4),
            }
        )
    payload = {
        "packet_type": "mim-context-grounded-conversation-scorecard-v1",
        "objective_id": "MIM-CONTEXT-GROUNDED-CONVERSATION-V1",
        "generated_at": utc_now(),
        "suite_path": str(suite_path),
        "reply_source": "live_public_chat_plus_ideal_nonpublic" if live_base_url else ("provided_replies" if replies_path else "ideal_reply_baseline"),
        "status": "target_met" if total_weight and weighted_pass / total_weight >= float(suite.get("target_pass_rate") or 0.9) else "needs_training",
        "case_count": len(cases),
        "pass_count": pass_count,
        "pass_rate": round(pass_count / max(1, len(cases)), 4),
        "weighted_pass_rate": round(weighted_pass / total_weight, 4) if total_weight else 0.0,
        "weighted_context_score": round((weighted_score / total_weight) * 10.0, 1) if total_weight else 0.0,
        "target_weighted_pass_rate": float(suite.get("target_pass_rate") or 0.9),
        "metrics": metrics,
        "cases": cases,
        "next_action": {
            "recommended_action": "Run this scorecard against exported live replies from every MIM surface and fail any reply that does not cite the right current-turn, prior-turn, page, upload, or project context.",
            "owner": "MIM + TOD",
            "expected_evidence": "Fresh MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json with live replies and failed cases converted into training examples.",
            "aging_rule": "Rerun after every MIM prompt/routing update and within 24h if any context-grounding dimension drops below 90%.",
            "dave_needed": "no",
        },
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    if markdown_path:
        write_markdown(markdown_path, payload)
    return payload


def write_markdown(path: Path, payload: dict[str, Any]) -> None:
    failures = [case for case in payload.get("cases") or [] if not case.get("passed")]
    lines = [
        "# MIM Context-Grounded Conversation Scorecard",
        "",
        f"Generated: {payload['generated_at']}",
        f"Status: {payload['status']}",
        f"Weighted pass rate: {payload['weighted_pass_rate']}",
        f"Weighted context score: {payload['weighted_context_score']}/10",
        f"Cases: {payload['pass_count']}/{payload['case_count']} passed",
        "",
        "## Dimension Coverage",
        "",
    ]
    for row in payload.get("metrics") or []:
        lines.append(f"- {row['metric']}: {row['passed']}/{row['total']} ({row['pass_rate']})")
    lines.extend(["", "## Failed Cases"])
    if failures:
        for case in failures[:25]:
            lines.append(f"- {case.get('scenario_id')}: {', '.join(case.get('failures') or [])}")
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
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--markdown-output", default=str(DEFAULT_MARKDOWN_OUTPUT))
    parser.add_argument("--replies", default=None, help="Optional JSON with replies: [{scenario_id, reply}].")
    parser.add_argument("--live-base-url", default=None, help="Optional public MIM base URL for public-chat cases.")
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
                "weighted_context_score": payload["weighted_context_score"],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
