#!/usr/bin/env python3
"""Run a broad Studio-specific MIM training/evaluation suite.

The suite focuses on the Studio operator chat surface: diagnostics, objective
continuation, scorecards, artifacts, projects, page actions, TOD handoffs, and
Dave-needed decisions. It is intentionally larger than the narrow live-10 and
durability guards so regressions like "continue objective -> repeat status" are
caught.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUT_JSON = ROOT / "runtime_remote_training" / "MIM_STUDIO_INTERACTION_TRAINING_SUITE.latest.json"
OUT_MD = ROOT / "runtime_remote_training" / "MIM_STUDIO_INTERACTION_TRAINING_SUITE.latest.md"


@dataclass(frozen=True)
class Case:
    case_id: str
    category: str
    prompt: str
    page_context: str
    expect: tuple[str, ...]
    forbidden: tuple[str, ...] = ()


EXPECT_PATTERNS: dict[str, re.Pattern[str]] = {
    "action": re.compile(r"\b(next action|recommended action|continue|started|run|inspect|repair|prove|publish|rerun|open|update)\b", re.I),
    "owner": re.compile(r"\b(owner|MIM|TOD|Codex|Dave)\b", re.I),
    "evidence": re.compile(r"\b(evidence|artifact|proof|validation|scoreboard|reflection|result|source|record)\b", re.I),
    "aging": re.compile(r"\b(aging|after|within|next cycle|24|48|72|stale|rerun|until|time)\b", re.I),
    "dave_needed": re.compile(r"\b(Dave needed|Dave is not needed|Dave is needed|Dave|no, unless|not needed)\b", re.I),
    "diagnosis": re.compile(r"\b(failure|problem|root|cause|stuck|blocked|regression|symptom|diagnose)\b", re.I),
    "objective_started": re.compile(r"\b(objective id|task id|objective continued|action_started|continuing the suggested training objective)\b", re.I),
    "scorecard": re.compile(r"\b(scorecard|scoreboard|MIM Communication|TOD|Outcome|Validated edits|Operator Impact|Active stale artifacts)\b", re.I),
    "active_stale_zero": re.compile(r"\b(active stale artifacts? (are )?0|Active stale artifacts:\s*0|active stale artifact count is 0)\b", re.I),
    "historical_artifacts": re.compile(r"\b(raw historical|retired|historical|superseded)\b", re.I),
    "project_movement": re.compile(r"\b(project|objective|terminal|successor|blocked|acceptance|moved|close|split|dispatch)\b", re.I),
    "page_context": re.compile(r"\b(Studio|training page|this page|page|surface)\b", re.I),
    "plain_answer": re.compile(r"\b(because|means|plain|summary|short version|what matters|current)\b", re.I),
}

FORBIDDEN_PATTERNS: dict[str, re.Pattern[str]] = {
    "fetch_failed": re.compile(r"Failed to fetch|chat failed from Studio", re.I),
    "status_repeat": re.compile(r"Here are the current scorecard numbers", re.I),
    "stale_unknown": re.compile(r"Stale artifacts:\s*unknown", re.I),
    "stale_four_active": re.compile(r"stale artifact count is 4", re.I),
    "lazy_clarify": re.compile(r"can you clarify|please clarify|what specifically do you mean", re.I),
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


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


def extract_reply(data: Any) -> str:
    if isinstance(data, str):
        return data.strip()
    if not isinstance(data, dict):
        return ""
    for key in ("reply_text", "message", "response", "content", "text"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    for key in ("mim_interface", "reply", "result", "resolution"):
        value = data.get(key)
        if isinstance(value, dict):
            reply = extract_reply(value)
            if reply:
                return reply
    return ""


def post_studio(base_url: str, case: Case, session_key: str, timeout: int, username: str, password: str) -> dict[str, Any]:
    payload = {
        "message": case.prompt,
        "prompt": case.prompt,
        "conversation_session_id": session_key,
        "page_context": case.page_context,
        "studio_page_context": case.page_context,
        "metadata_json": {
            "surface": "studio_training_broad_suite",
            "suite_case_id": case.case_id,
            "suite_category": case.category,
        },
    }
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json, text/plain, */*",
        "User-Agent": "MIM Studio interaction training suite/1.0",
    }
    if username or password:
        token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
        headers["Authorization"] = f"Basic {token}"
    request = urllib.request.Request(
        base_url.rstrip("/") + "/studio/api/mim/chat",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.loads(response.read().decode("utf-8", errors="replace"))
    return data if isinstance(data, dict) else {"raw": data}


def build_cases() -> list[Case]:
    groups: list[tuple[str, str, list[str], tuple[str, ...], tuple[str, ...]]] = [
        (
            "diagnosis",
            "Studio Training",
            [
                "H.A.L.: diagnose this Studio page and current MIM/TOD state. Find what is stuck.",
                "No training improvements?",
                "Is anything stuck?",
                "Why did MIM just repeat status instead of continuing?",
                "What failed in the Studio training page workflow?",
                "Find the root cause of the current training gap.",
            ],
            ("diagnosis", "action", "owner", "evidence", "dave_needed"),
            ("fetch_failed", "lazy_clarify"),
        ),
        (
            "continue_objective",
            "Studio Training",
            [
                "Yes continue with this objective: artifacts.",
                "Continue the suggested objective.",
                "Go ahead and continue the artifact objective.",
                "Do it. Start the training-resolution objective.",
                "Proceed with the recommended objective.",
                "Keep going with outcome reflection artifacts.",
            ],
            ("objective_started", "action", "owner", "evidence", "active_stale_zero", "historical_artifacts"),
            ("status_repeat", "stale_unknown", "fetch_failed"),
        ),
        (
            "scorecard",
            "Studio Training",
            [
                "What are the current scorecard numbers?",
                "Give me the Studio scorecard.",
                "Show MIM and TOD metrics.",
                "What is Tod's current Training scorecard data?",
                "What are the current training metrics?",
                "Show the outcome numbers.",
            ],
            ("scorecard", "active_stale_zero", "historical_artifacts", "evidence"),
            ("stale_unknown", "stale_four_active", "fetch_failed"),
        ),
        (
            "recommendation",
            "Studio Training",
            [
                "Give me one Studio recommendation for today.",
                "What should happen next?",
                "What is the highest value Studio action?",
                "Which training item matters most?",
                "What should MIM prioritize now?",
                "What should TOD focus on next?",
            ],
            ("action", "owner", "evidence", "aging", "dave_needed"),
            ("status_repeat", "fetch_failed"),
        ),
        (
            "artifact_workthrough",
            "Studio Training",
            [
                "Walk through the artifact cleanup objective.",
                "Which artifacts are still active blockers?",
                "Explain active stale versus historical retired artifacts.",
                "What proof would retire an artifact safely?",
                "How should artifacts be mapped to current truth?",
                "What artifact evidence should TOD publish?",
            ],
            ("active_stale_zero", "historical_artifacts", "evidence", "action"),
            ("stale_unknown", "stale_four_active", "fetch_failed"),
        ),
        (
            "project_movement",
            "Studio Projects",
            [
                "Which project needs movement?",
                "How should a stale project be forced into a successor state?",
                "What project should be closed, split, blocked, or dispatched?",
                "What proves a project moved toward completion?",
                "How do we prevent project status theater?",
                "What should happen to needs-review work?",
            ],
            ("project_movement", "action", "owner", "evidence", "dave_needed"),
            ("fetch_failed", "lazy_clarify"),
        ),
        (
            "page_function",
            "Studio Training",
            [
                "What page function should I use to start a repair?",
                "Where should I look on this page for evidence?",
                "What should the Training page show after the repair?",
                "How should MIM use this Studio page context?",
                "What should the chat do when I say continue?",
                "What should happen if Studio chat fetch fails?",
            ],
            ("page_context", "action", "evidence", "owner"),
            ("fetch_failed",),
        ),
        (
            "tod_handoff",
            "Studio TOD",
            [
                "What should TOD do with the current blocker?",
                "How should TOD prove an inspected blocker?",
                "What should TOD publish before getting independent-resolution credit?",
                "What is missing for TOD to reach 10 independent resolutions?",
                "Should TOD continue autonomously?",
                "What handoff evidence does Codex need if TOD stalls?",
            ],
            ("action", "owner", "evidence", "aging", "dave_needed"),
            ("status_repeat", "fetch_failed"),
        ),
        (
            "plain_explanation",
            "Studio Training",
            [
                "Explain this to me plainly.",
                "What does outcomes improving false mean?",
                "Why is training running but not improving?",
                "Why is active stale zero not enough?",
                "What changed after the artifact fix?",
                "Summarize the Studio training state without dumping the scoreboard.",
            ],
            ("plain_answer", "action", "evidence"),
            ("status_repeat", "fetch_failed"),
        ),
        (
            "dave_needed",
            "Studio Training",
            [
                "Do you need Dave for this?",
                "What decision is waiting on me?",
                "Can MIM and TOD continue without Dave?",
                "When should this escalate to Codex?",
                "Who owns the next action?",
                "What is the aging rule before Dave is needed?",
            ],
            ("owner", "dave_needed", "action", "aging"),
            ("fetch_failed", "lazy_clarify"),
        ),
    ]
    cases: list[Case] = []
    variants = [
        "",
        " Be concise.",
        " Show evidence.",
        " Classify the failure.",
        " Do not repeat status.",
        " Include owner and next action.",
        " Include Dave needed yes or no.",
    ]
    for category, page_context, prompts, expect, forbidden in groups:
        for prompt in prompts:
            for variant in variants:
                case_id = f"{category}-{len(cases)+1:03d}"
                cases.append(Case(case_id, category, f"{prompt}{variant}".strip(), page_context, expect, forbidden))
    return cases


def score_case(case: Case, data: dict[str, Any] | None, error: str | None) -> dict[str, Any]:
    reply = extract_reply(data or {})
    combined = " ".join(
        part
        for part in [
            reply,
            str((data or {}).get("source") or ""),
            str((data or {}).get("response_mode") or ""),
            json.dumps((data or {}).get("evidence") or {}, sort_keys=True),
        ]
        if part
    )
    checks = {name: bool(EXPECT_PATTERNS[name].search(combined)) for name in case.expect}
    forbidden_hits = [
        name
        for name in case.forbidden
        if name in FORBIDDEN_PATTERNS and FORBIDDEN_PATTERNS[name].search(combined)
    ]
    if error:
        forbidden_hits.append("request_error")
    passed = all(checks.values()) and not forbidden_hits and bool(reply)
    return {
        "case_id": case.case_id,
        "category": case.category,
        "page_context": case.page_context,
        "prompt": case.prompt,
        "passed": passed,
        "checks": checks,
        "missing": [name for name, value in checks.items() if not value],
        "forbidden_hits": forbidden_hits,
        "source": (data or {}).get("source", ""),
        "response_mode": (data or {}).get("response_mode", ""),
        "reply_excerpt": reply[:900],
        **({"error": error} if error else {}),
    }


def write_markdown(packet: dict[str, Any]) -> None:
    summary = packet["summary"]
    lines = [
        "# MIM Studio Interaction Training Suite",
        "",
        f"Generated: {packet['generated_at']}",
        f"Status: {packet['status']}",
        f"Cases: {summary['case_count']}",
        f"Passed: {summary['passed']}",
        f"Failed: {summary['failed']}",
        f"Pass rate: {summary['pass_rate_percent']}%",
        "",
        "## Category Results",
        "",
        "| Category | Passed | Failed | Pass Rate |",
        "|---|---:|---:|---:|",
    ]
    for category, row in packet["category_summary"].items():
        lines.append(f"| {category} | {row['passed']} | {row['failed']} | {row['pass_rate_percent']}% |")
    lines.extend(["", "## Failed Cases", ""])
    failed = [case for case in packet["cases"] if not case.get("passed")]
    if not failed:
        lines.append("- None.")
    else:
        for case in failed[:80]:
            missing = ", ".join(case.get("missing") or [])
            forbidden = ", ".join(case.get("forbidden_hits") or [])
            lines.append(f"- {case['case_id']} `{case['category']}`: missing [{missing}] forbidden [{forbidden}] prompt: {case['prompt']}")
        if len(failed) > 80:
            lines.append(f"- ... {len(failed) - 80} more failed cases in JSON.")
    OUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.getenv("MIM_STUDIO_BASE_URL", "https://mim.mimtod.com"))
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--max-cases", type=int, default=420)
    parser.add_argument("--studio-username", default=None)
    parser.add_argument("--studio-password", default=None)
    args = parser.parse_args()

    load_dotenv(ROOT / ".env")
    load_dotenv(ROOT / "tmp_remote_mim" / ".env")
    username = args.studio_username or os.getenv("MIMTOD_USER", "")
    password = args.studio_password or os.getenv("MIMTOD_PASSWORD", "")

    generated = utc_now()
    cases = build_cases()[: max(1, args.max_cases)]
    scored: list[dict[str, Any]] = []
    for index, case in enumerate(cases, start=1):
        data: dict[str, Any] | None = None
        error: str | None = None
        try:
            data = post_studio(args.base_url, case, f"studio-training-suite-{generated}-{index}", args.timeout, username, password)
        except Exception as exc:
            if isinstance(exc, urllib.error.HTTPError):
                try:
                    body = exc.read().decode("utf-8", errors="replace")
                except Exception:
                    body = ""
                error = f"HTTP {exc.code}: {body[:240]}"
            else:
                error = " ".join(str(exc).split())[:300]
        scored.append(score_case(case, data, error))

    passed = sum(1 for item in scored if item["passed"])
    category_summary: dict[str, dict[str, int]] = {}
    for category in sorted({case.category for case in cases}):
        items = [item for item in scored if item["category"] == category]
        category_passed = sum(1 for item in items if item["passed"])
        total = len(items)
        category_summary[category] = {
            "passed": category_passed,
            "failed": total - category_passed,
            "pass_rate_percent": round((category_passed / total) * 100) if total else 0,
        }
    total = len(scored)
    packet = {
        "packet_type": "mim-studio-interaction-training-suite-v1",
        "objective_id": "MIM-STUDIO-INTERACTION-TRAINING-300-500-V1",
        "generated_at": generated,
        "status": "target_met" if total and passed / total >= 0.9 else "needs_training",
        "base_url": args.base_url,
        "summary": {
            "case_count": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate_percent": round((passed / total) * 100) if total else 0,
            "target_pass_rate_percent": 90,
        },
        "category_summary": category_summary,
        "cases": scored,
        "recommended_action": "Convert failed Studio interaction categories into targeted route/prompt repairs, then rerun this 420-case suite before calling Studio training improved.",
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(packet)
    print(json.dumps({"status": packet["status"], **packet["summary"]}, indent=2))
    return 0 if packet["status"] == "target_met" else 2


if __name__ == "__main__":
    raise SystemExit(main())
