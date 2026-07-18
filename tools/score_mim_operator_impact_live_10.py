"""Score 10 live Studio MIM operator replies for the operator-impact contract."""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import traceback
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "runtime_remote_training" / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
OUTPUT_MD_PATH = ROOT / "runtime_remote_training" / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.md"
OPERATOR_SCORECARD_PATH = ROOT / "runtime_remote_training" / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json"
REAL_MOVEMENT_PATH = ROOT / "runtime_remote_training" / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"

FIELD_RULES = {
    "actionability": re.compile(r"\b(next step|next action|action:|recommended action|recommendation:|i recommend|should|start|run|inspect|repair|rerun)\b", re.I),
    "owner_assignment": re.compile(r"\b(owner|MIM|TOD|Codex|Dave|external dependency)\b", re.I),
    "expected_evidence": re.compile(r"\b(evidence|artifact|result|proof|validation|reflection|scoreboard|record|source)\b", re.I),
    "time_aging_rule": re.compile(r"\b(hour|daily|weekly|24h|48h|72h|7d|aging|stale|rerun|after the next|within)\b", re.I),
    "dave_needed": re.compile(r"\b(Dave needed|Dave is needed|Dave is not needed|Dave: yes|Dave: no|no Dave|unless .+Dave)\b", re.I),
}

STATUS_LEAKAGE_PATTERN = re.compile(
    r"\b("
    r"training is active, but the useful question is whether it is changing behavior|"
    r"right now my mode-selection score|"
    r"the outcome verdict is|"
    r"i default to status reporting instead of selecting"
    r")\b",
    re.I,
)

PROMPTS = [
    ("training_status", "how is training going MIM?"),
    ("blockers", "any blockers?"),
    ("next_work", "is there anything you want to work on next?"),
    ("more_training", "tell me more about your training MIM"),
    ("scorecard_attention", "the training page says needs attention. what should happen now?"),
    ("project_blocked", "why is the current project blocked?"),
    ("operator_priority", "what is the highest value task right now?"),
    ("status_dump_regression", "MIM gave me a status dump again. what should happen?"),
    ("tod_validated_edits", "Validated TOD Edits is still 1. what should TOD do next?"),
    ("auth_surface_block", "cross-surface scoring is blocked by auth. what is the next action?"),
]


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def prior_operator_impact_summary() -> str:
    operator = load_json(OPERATOR_SCORECARD_PATH)
    score = operator.get("operator_impact_score")
    sample_count = operator.get("sample_count")
    try:
        if float(score) > 0 and int(sample_count) > 0:
            return f"{float(score):.1f}/10 from {int(sample_count)} live replies"
    except (TypeError, ValueError):
        pass
    real_movement = load_json(REAL_MOVEMENT_PATH)
    for row in real_movement.get("metrics") if isinstance(real_movement.get("metrics"), list) else []:
        if not isinstance(row, dict) or row.get("metric") != "MIM Operator Impact":
            continue
        current = str(row.get("current") or "").strip()
        if re.search(r"\b(?!0\.0/10 from 0 live replies)\d+(?:\.\d+)?/10 from \d+ live replies\b", current):
            return current
    return ""


def post_studio_turn(base_url: str, username: str, password: str, session_key: str, message: str, timeout: int) -> str:
    payload = json.dumps(
        {
            "message": message,
            "prompt": message,
            "conversation_session_id": session_key,
            "page_context": "Studio Training",
            "metadata_json": {"surface": "studio_training_operator_impact"},
        },
        ensure_ascii=False,
    ).encode("utf-8")
    token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(
        base_url.rstrip("/") + "/studio/api/mim/chat",
        data=payload,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json, text/plain, */*",
            "Authorization": f"Basic {token}",
            "User-Agent": "MIM operator-impact live-10 scorer/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.loads(response.read().decode("utf-8", errors="replace"))
    return extract_reply(data)


def extract_reply(data: Any) -> str:
    if isinstance(data, str):
        return data.strip()
    if not isinstance(data, dict):
        return ""
    for key in ("reply_text", "message", "response", "content", "text"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    for key in ("reply", "mim_interface", "result"):
        value = data.get(key)
        if isinstance(value, dict):
            reply = extract_reply(value)
            if reply:
                return reply
    return ""


def score_reply(reply: str) -> dict[str, Any]:
    field_scores = {key: bool(pattern.search(reply)) for key, pattern in FIELD_RULES.items()}
    status_only = not field_scores["actionability"] and bool(re.search(r"\b(status|scoreboard|active|running|summary|currently|progress)\b", reply, re.I))
    status_leakage = bool(STATUS_LEAKAGE_PATTERN.search(reply))
    passed_fields = sum(1 for passed in field_scores.values() if passed)
    score_10 = round((passed_fields / len(FIELD_RULES)) * 10, 1)
    if status_only:
        score_10 = max(0.0, score_10 - 2.0)
    if status_leakage:
        score_10 = min(score_10, 6.0)
    return {
        "field_scores": field_scores,
        "passed_field_count": passed_fields,
        "required_field_count": len(FIELD_RULES),
        "status_only": status_only,
        "status_leakage": status_leakage,
        "score_10": score_10,
        "passed": passed_fields == len(FIELD_RULES) and not status_only and not status_leakage,
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    load_dotenv(ROOT / "tmp_remote_mim" / ".env")
    username = args.studio_username or os.getenv("MIMTOD_USER", "")
    password = args.studio_password or os.getenv("MIMTOD_PASSWORD", "")
    if not username or not password:
        raise SystemExit("MIMTOD_USER/MIMTOD_PASSWORD are required for live operator-impact scoring")
    generated = utc_now()
    scored_cases = []
    field_counts = {key: 0 for key in FIELD_RULES}
    for idx, (case_id, prompt) in enumerate(PROMPTS, start=1):
        reply = post_studio_turn(args.studio_base_url, username, password, f"operator-impact-live-10-{generated}-{idx}", prompt, args.timeout)
        scored = score_reply(reply)
        for key, passed in scored["field_scores"].items():
            if passed:
                field_counts[key] += 1
        scored.update({"id": case_id, "prompt": prompt, "reply_excerpt": reply[:700], "source": "studio_api_mim_chat"})
        scored_cases.append(scored)
    sample_count = len(scored_cases)
    pass_count = sum(1 for item in scored_cases if item["passed"])
    total_score = sum(float(item["score_10"]) for item in scored_cases)
    operator_score = round(total_score / sample_count, 1) if sample_count else 0.0
    operator_percent = round(operator_score * 10)

    def field_current(field: str) -> str:
        passed = field_counts.get(field, 0)
        percent = round((passed / sample_count) * 100) if sample_count else 0
        return f"{percent}% / {passed} of {sample_count}"

    metrics = [
        {"metric": "Operator Impact", "baseline": "6/10", "current": f"{operator_score}/10 from {sample_count} live replies", "source": "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"},
        {"metric": "Actionability Score", "baseline": "live-10 baseline", "current": field_current("actionability"), "source": "specific recommended action present"},
        {"metric": "Owner Assignment", "baseline": "live-10 baseline", "current": field_current("owner_assignment"), "source": "reply names MIM, TOD, Codex, external dependency, or Dave"},
        {"metric": "Expected Evidence", "baseline": "live-10 baseline", "current": field_current("expected_evidence"), "source": "reply states artifact/result/proof/validation expected"},
        {"metric": "Time / Aging Rule", "baseline": "live-10 baseline", "current": field_current("time_aging_rule"), "source": "reply includes timing, stale threshold, or escalation age"},
        {"metric": "Dave Needed Clarity", "baseline": "live-10 baseline", "current": field_current("dave_needed"), "source": "reply says Dave needed yes/no or exception"},
        {
            "metric": "Status Leakage",
            "baseline": "live-10 baseline",
            "current": f"{sum(1 for item in scored_cases if item.get('status_leakage'))} of {sample_count}",
            "source": "status-dump phrasing must not pass by containing the five required fields",
        },
    ]
    return {
        "packet_type": "mim-operator-impact-live-10-scorecard-v1",
        "objective_id": "MIM-OPERATOR-IMPACT-REGRESSION-REPAIR-V1",
        "generated_at": generated,
        "status": "target_met" if operator_score >= 8 and pass_count >= 8 else "needs_repair",
        "sample_count": sample_count,
        "pass_count": pass_count,
        "operator_impact_score": operator_score,
        "operator_impact_percent": operator_percent,
        "required_fields": list(FIELD_RULES.keys()),
        "metrics": metrics,
        "scored_cases": scored_cases,
        "next_action": "Keep this live-10 guard in the training scoreboard and rerun after response-policy changes.",
    }


def write_report(report: dict[str, Any]) -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    lines = [
        "# MIM Operator Impact Live 10 Scorecard",
        "",
        f"Generated: {report['generated_at']}",
        f"Status: {report['status']}",
        f"Operator impact: {report['operator_impact_score']}/10",
        f"Pass count: {report['pass_count']}/{report['sample_count']}",
        "",
        "## Metrics",
        "",
    ]
    for row in report["metrics"]:
        lines.append(f"- {row['metric']}: {row['current']}")
    OUTPUT_MD_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_blocked_report(args: argparse.Namespace, exc: BaseException) -> dict[str, Any]:
    generated = utc_now()
    prior_summary = prior_operator_impact_summary()
    attempted_command = " ".join(
        [
            "python",
            "tools/score_mim_operator_impact_live_10.py",
            "--studio-base-url",
            str(args.studio_base_url),
            "--timeout",
            str(args.timeout),
        ]
    )
    error_text = f"{exc.__class__.__name__}: {exc}"
    return {
        "packet_type": "mim-operator-impact-live-10-scorecard-v1",
        "objective_id": "MIM-OPERATOR-IMPACT-REGRESSION-REPAIR-V1",
        "generated_at": generated,
        "status": "blocked",
        "blocker_class": "live_validation_blocked",
        "reason_code": "studio_live_post_failed",
        "attempted_command": attempted_command,
        "error": error_text,
        "traceback_excerpt": traceback.format_exc(limit=6),
        "sample_count": 0,
        "pass_count": 0,
        "operator_impact_score": 0.0,
        "operator_impact_percent": 0,
        "required_fields": list(FIELD_RULES.keys()),
        "metrics": [
            {
                "metric": "Operator Impact",
                "baseline": "6/10",
                "current": "blocked: live scorer could not collect Studio replies",
                "source": "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json",
            },
            {
                "metric": "Live Validation Blocker",
                "baseline": "live Studio POST succeeds",
                "current": error_text,
                "source": "tools/score_mim_operator_impact_live_10.py",
            },
        ],
        "scored_cases": [],
        "last_verified_operator_impact": prior_summary,
        "owner": "TOD/MIM live-validation lane",
        "expected_evidence": [
            "POST to /studio/api/mim/chat succeeds from the scorer runtime",
            "10 Studio replies are scored",
            "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json has sample_count=10",
            "operator_impact_score reaches at least 8.0",
        ],
        "aging_rule": "Retry from an authorized live-validation runtime within 24h; if blocked again, publish the scorer error and keep the prior real-movement score as the displayed truth.",
        "dave_needed": "no unless all TOD/MIM live-validation runtimes lack network or credentials",
        "prevention_lesson": "A blocked live scorer must still write a durable blocked artifact so Studio Training can distinguish missing evidence from successful-but-unpublished scoring.",
        "next_action": "Run this scorer from a runtime that can reach Studio, then rebuild operator-impact and real-movement scorecards.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio-base-url", default=os.getenv("MIM_STUDIO_BASE_URL", "https://mimtod.com"))
    parser.add_argument("--studio-username", default=None)
    parser.add_argument("--studio-password", default=None)
    parser.add_argument("--timeout", type=int, default=45)
    args = parser.parse_args()
    try:
        report = build_report(args)
    except Exception as exc:
        report = build_blocked_report(args, exc)
        write_report(report)
        print(
            json.dumps(
                {
                    "status": report["status"],
                    "blocker_class": report["blocker_class"],
                    "error": report["error"],
                    "artifact": str(OUTPUT_PATH),
                },
                indent=2,
            ),
            file=sys.stderr,
        )
        return 2
    write_report(report)
    print(json.dumps({"status": report["status"], "operator_impact_score": report["operator_impact_score"], "pass_count": report["pass_count"], "sample_count": report["sample_count"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
