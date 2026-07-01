#!/usr/bin/env python3
"""Run MIM conversation-mode durability smoke V2.

This smoke checks whether MIM selects the right conversational mode before
answering normal user prompts. It is intentionally stricter than a keyword
score: operator-status scaffolding must fail on normal conversation prompts.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUT_ROOT = ROOT / "runtime_remote_training"


GROUPS = {
    "recommendation_mode": [
        "What should we work on next?",
        "What is highest priority?",
        "What would create the most value?",
        "Which project should MIM push first today?",
        "What should happen before we add another feature?",
        "Which blocker would create the most leverage if cleared?",
        "What is the best next training objective?",
        "What should TOD focus on next?",
        "What is the highest value task right now?",
        "Where should we spend the next hour?",
        "Which training item matters most before Dave leaves?",
        "What should we fix first?",
        "What is the next useful action?",
        "Which project has the best payoff today?",
        "What should MIM prioritize this morning?",
        "What is the smartest next move?",
        "What work should be paused?",
        "What should be closed before new work starts?",
        "Which blocker is most expensive?",
        "What is the best next operator action?",
    ],
    "explanation_mode": [
        "Explain it to a non-technical user.",
        "Summarize the proposal.",
        "What did we learn?",
        "What changed today?",
        "What is TOD working on?",
        "What do you need from Dave?",
        "Explain why the training page says needs attention.",
        "Explain the difference between stale ledger blockers and current blockers.",
        "What does regression guard mean?",
        "Explain why 20 out of 20 is not enough anymore.",
        "What are you working on MIM?",
        "How is training going MIM?",
        "Tell me more about your training MIM.",
        "What changed since the last cycle?",
        "Explain the current training score in plain language.",
        "Why is operator impact important?",
        "What does validated TOD edit mean?",
        "What is an independent TOD resolution?",
        "What does stale artifact count mean?",
        "Explain why structural reasoning matters.",
    ],
    "demonstration_mode": [
        "Show me a sample.",
        "What would this look like?",
        "Can I see an example?",
        "Show me the interface.",
        "Show me what a project completion proof should look like.",
        "Give me an example of a continuity brief.",
        "Show me a sample MIM recommendation brief.",
        "What would a clean Dave-needed approval card look like?",
        "Show me a sample project status reply.",
        "Can you demonstrate the next action format?",
        "Show me a prototype outline.",
        "Can I see a sample dashboard layout?",
        "Show me what a clean blocker report looks like.",
        "Give me an example support ticket handoff.",
        "Show me a sample commission reconciliation plan.",
        "What would the user-facing answer look like?",
        "Show me a sample training result card.",
        "Can you show a before and after reply?",
        "Show me how TOD should prove a fix.",
        "Give me a concrete example.",
    ],
    "consultative_discovery": [
        "Build me an accounting app.",
        "I need inventory management.",
        "I want an app like Connecteam.",
        "I want MIM to manage my social channels.",
        "I need a project page that keeps work from going stale.",
        "I want TOD to choose its own next task.",
        "I need AgentMIM reports to show real customer data.",
        "Build me a CRM.",
        "I need a scheduling system.",
        "Build a receipt tracking app.",
        "Can AI help my business?",
        "I need a better system.",
        "I want something like Salesforce.",
        "Build a mobile app for dog groomers.",
        "I need to automate commissions.",
        "I want a client portal.",
        "Build a simple applicant tracker.",
        "I need a dashboard for sales reps.",
        "I want software for monthly expenses.",
        "Build an app for field service scheduling.",
    ],
    "problem_analysis": [
        "Are you stuck?",
        "Why did this objective fail?",
        "How do we prevent this again?",
        "What is the biggest problem right now?",
        "Why are projects moving but not closing?",
        "Why did MIM answer with the training scoreboard instead of the project answer?",
        "Why are the scorecards unchanged all week?",
        "Why does TOD stop after selecting a next action?",
        "Why did this fail?",
        "Why is this blocked?",
        "Why doesn't this work?",
        "Why did upload processing time out?",
        "Why did MIM ask for the carrier when the carrier column exists?",
        "Why did the dashboard total not match?",
        "How do we prevent status dumps?",
        "Why are internal task IDs leaking?",
        "Why did the image regeneration get stuck?",
        "Why are stale artifacts still showing?",
        "Why did TOD not materialize a patch?",
        "What caused the training score to drop?",
    ],
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
    for key in ("reply", "mim_interface", "resolution", "result"):
        value = data.get(key)
        if isinstance(value, dict):
            reply = extract_reply(value)
            if reply:
                return reply
    return ""


def post_gateway(base_url: str, prompt: str, timeout: int) -> str:
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
            "test": "mim_durability_smoke_v2",
        },
    }
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/gateway/intake",
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return extract_reply(json.loads(response.read().decode("utf-8", errors="replace")))


def post_studio(base_url: str, prompt: str, timeout: int, session_key: str) -> str:
    load_dotenv(ROOT / "tmp_remote_mim" / ".env")
    username = os.getenv("MIMTOD_USER", "")
    password = os.getenv("MIMTOD_PASSWORD", "")
    if not username or not password:
        raise RuntimeError("MIMTOD_USER/MIMTOD_PASSWORD are required for studio transport")
    payload = {
        "message": prompt,
        "prompt": prompt,
        "conversation_session_id": session_key,
        "page_context": "Studio Training",
        "metadata_json": {
            "surface": "studio_training_conversation_mode_durability",
            "route_preference": "conversation_layer",
            "test": "mim_durability_smoke_v2",
        },
    }
    token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/studio/api/mim/chat",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json, text/plain, */*",
            "Authorization": f"Basic {token}",
            "User-Agent": "MIM durability smoke v2/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return extract_reply(json.loads(response.read().decode("utf-8", errors="replace")))


def has_any(text: str, terms: tuple[str, ...]) -> bool:
    lowered = text.lower()
    return any(term in lowered for term in terms)


def count_questions(text: str) -> int:
    return text.count("?")


def no_raw_runtime_language(reply: str) -> bool:
    patterns = (
        r"\btask\s+\d{3,}\b",
        r"\bobjective-\d+\b",
        r"\bobjective\s+\d{3,}\b",
        r"\brequest[_ -]?id\b",
        r"\blifecycle\b",
        r"\bpacket\b",
        r"\bGET\s+/",
        r"\bpass bar\b",
        r"\bcontinuation policy\b",
        r"\bMIM_[A-Z0-9_]+\.latest\.(json|md)\b",
    )
    return not any(re.search(pattern, reply, flags=re.IGNORECASE) for pattern in patterns)


def not_generic_deflection(reply: str) -> bool:
    return not has_any(
        reply,
        (
            "ask me about",
            "i can answer that directly",
            "let me know if you want",
            "please provide the details",
            "what would you like to explore or work on today",
        ),
    )


def no_status_report_leakage(reply: str) -> bool:
    status_patterns = (
        "training is active, but outcome improvement is not proven yet",
        "training is active, but the useful question is whether it is changing behavior",
        "my current weakness is:",
        "my mode-selection score",
        "the outcome verdict is",
        "i default to status reporting",
        "not whether the scoreboard looks busy",
        "here are the current scorecard numbers",
        "current evidence:",
        "recommended action:",
        "expected evidence:",
        "time / aging rule:",
        "dave needed:",
        "mim communication:",
        "mim/tod real movement:",
        "mim operator impact:",
    )
    lowered = reply.lower()
    return not any(pattern in lowered for pattern in status_patterns)


def mode_identity(mode: str, reply: str) -> bool:
    lowered = reply.lower()
    if mode == "explanation_mode":
        recommendation_openers = (
            "i recommend ",
            "recommended action:",
            "the next action is",
            "owner:",
            "expected evidence:",
            "time / aging rule:",
            "dave needed:",
        )
        return not any(term in lowered for term in recommendation_openers)
    if mode == "recommendation_mode":
        return has_any(reply, ("recommend", "highest value", "priority", "should", "next", "focus"))
    if mode == "demonstration_mode":
        return has_any(reply, ("sample", "example", "looks like", "prototype", "interface", "card", "before", "after"))
    if mode == "consultative_discovery":
        return has_any(reply, ("first", "workflow", "system", "process", "goal", "users", "data", "question"))
    if mode == "problem_analysis":
        return has_any(reply, ("problem", "root", "cause", "failed", "blocked", "prevent", "because", "fix"))
    return True


def evaluate(mode: str, prompt: str, reply: str) -> dict[str, Any]:
    lowered = reply.lower()
    common = {
        "no_raw_runtime_language": no_raw_runtime_language(reply),
        "not_generic_deflection": not_generic_deflection(reply),
        "no_status_report_leakage": no_status_report_leakage(reply),
        "mode_identity": mode_identity(mode, reply),
        "plain_enough": len(reply) >= 120,
    }
    if mode == "recommendation_mode":
        checks = {
            **common,
            "makes_recommendation": has_any(reply, ("recommend", "highest value", "priority", "should", "next")),
            "explains_why": has_any(reply, ("because", "why", "value", "impact", "matters")),
            "states_next_action": has_any(reply, ("next", "start", "work on", "focus")),
            "mentions_blocker_or_tradeoff": has_any(reply, ("blocker", "blocked", "risk", "tradeoff", "issue", "problem")),
        }
    elif mode == "explanation_mode":
        checks = {
            **common,
            "answers_without_asking_for_reprompt": not has_any(reply, ("which proposal", "provide the details", "ask me about")),
            "summarizes_or_explains": has_any(reply, ("summary", "means", "plain", "learned", "changed", "sample", "tod", "dave", "working", "training")),
            "states_useful_next_step": has_any(reply, ("next", "should", "open", "review", "need", "not needed", "focus", "keep")),
        }
    elif mode == "demonstration_mode":
        checks = {
            **common,
            "acknowledges_visual_or_sample_request": has_any(reply, ("sample", "example", "prototype", "interface", "preview", "look like", "visual")),
            "provides_access_or_honest_block": has_any(reply, ("open", "link", "card", "attached", "ready", "not ready", "missing", "blocked", "create")),
            "states_what_user_can_review": has_any(reply, ("review", "open", "view", "prototype", "sample", "example", "interface", "screenshot")),
            "states_next_step": has_any(reply, ("next", "if this is not", "tell me", "create", "revise", "provide")),
        }
    elif mode == "consultative_discovery":
        checks = {
            **common,
            "reframes_business_need": has_any(reply, ("platform", "workflow", "process", "system", "problem", "goal", "operations")),
            "identifies_hidden_requirements": has_any(reply, ("report", "role", "integration", "data", "approval", "audit", "notification", "compliance", "category")),
            "asks_limited_clarifying_questions": 1 <= count_questions(reply) <= 5,
            "does_not_clone_reference": "connecteam" not in lowered or has_any(reply, ("pattern", "not copy", "original", "safe", "workforce")),
            "offers_next_discovery_step": has_any(reply, ("next", "first", "start", "walk me through", "recommend")),
        }
    elif mode == "problem_analysis":
        checks = {
            **common,
            "states_problem_or_failure": has_any(reply, ("problem", "failed", "stuck", "blocked", "issue", "root", "cause")),
            "states_learning_or_prevention": has_any(reply, ("learn", "prevent", "again", "next time", "rule", "fix")),
            "states_next_action": has_any(reply, ("next", "repair", "resolve", "inspect", "continue", "work on")),
            "dave_needed_state": has_any(reply, ("dave", "you", "not needed", "no action", "need from")),
        }
    else:
        checks = common
    return {
        "mode": mode,
        "prompt": prompt,
        "passed": all(checks.values()),
        "checks": checks,
        "reply_length": len(reply),
        "reply_excerpt": reply[:700],
    }


def write_markdown(packet: dict[str, Any], path: Path) -> None:
    summary = packet["summary"]
    lines = [
        "# MIM Durability Smoke V2",
        "",
        f"Generated: {packet['generated_at']}",
        f"Status: {packet['status']}",
        f"Transport: {packet['transport']}",
        f"Base URL: {packet['base_url']}",
        "",
        "## Summary",
        "",
        f"- Cases: {summary['case_count']}",
        f"- Passed: {summary['passed']}",
        f"- Failed: {summary['failed']}",
        f"- Pass rate: {summary['pass_rate_percent']}%",
        f"- Status leakage failures: {summary['status_leakage_failures']}",
        "",
        "## Group Results",
        "",
        "| Group | Passed | Failed |",
        "|---|---:|---:|",
    ]
    for group, values in packet["group_summary"].items():
        lines.append(f"| {group.replace('_', ' ').title()} | {values['passed']} | {values['failed']} |")
    lines.extend(["", "## Failed Cases", ""])
    failed = [case for case in packet["cases"] if not case.get("passed")]
    if not failed:
        lines.append("- None.")
    else:
        for case in failed:
            missing = [key for key, value in case.get("checks", {}).items() if not value]
            lines.append(f"- {case['prompt']} ({case['mode']}): missing {', '.join(missing)}.")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://192.168.1.120:18001")
    parser.add_argument("--out-dir", default=str(OUT_ROOT))
    parser.add_argument("--transport", choices=("gateway", "studio"), default="gateway")
    parser.add_argument("--timeout", type=int, default=45)
    args = parser.parse_args()

    generated = utc_now()
    cases: list[dict[str, Any]] = []
    case_number = 0
    for mode, prompts in GROUPS.items():
        for prompt in prompts:
            case_number += 1
            try:
                if args.transport == "studio":
                    reply = post_studio(args.base_url, prompt, args.timeout, f"durability-v2-{generated}-{case_number}")
                else:
                    reply = post_gateway(args.base_url, prompt, args.timeout)
                case = evaluate(mode, prompt, reply)
            except Exception as exc:
                case = {
                    "mode": mode,
                    "prompt": prompt,
                    "passed": False,
                    "error": " ".join(str(exc).split())[:300],
                    "checks": {"live_eval_available": False},
                    "reply_excerpt": "",
                    "reply_length": 0,
                }
            cases.append(case)

    passed = sum(1 for case in cases if case.get("passed"))
    status_leakage_failures = sum(
        1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False
    )
    mode_identity_failures = sum(
        1 for case in cases if case.get("checks", {}).get("mode_identity") is False
    )
    group_summary: dict[str, dict[str, int]] = {}
    for mode in GROUPS:
        group_cases = [case for case in cases if case.get("mode") == mode]
        group_passed = sum(1 for case in group_cases if case.get("passed"))
        group_summary[mode] = {"passed": group_passed, "failed": len(group_cases) - group_passed}

    total = len(cases)
    packet = {
        "packet_type": "mim-durability-smoke-v2",
        "objective_id": "MIM-CONVERSATION-MODE-DURABILITY-SMOKE-V2",
        "generated_at": generated,
        "status": "passed" if passed == total else "failed_needs_judgment_training",
        "transport": args.transport,
        "base_url": args.base_url,
        "summary": {
            "case_count": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate_percent": round((passed / total) * 100) if total else 0,
            "status_leakage_checked_cases": total,
            "status_leakage_failures": status_leakage_failures,
            "status_leakage_pass_rate_percent": round(((total - status_leakage_failures) / total) * 100) if total else 0,
            "status_leakage_failure_rate_percent": round((status_leakage_failures / total) * 100) if total else 0,
            "mode_identity_failures": mode_identity_failures,
            "mode_identity_pass_rate_percent": round(((total - mode_identity_failures) / total) * 100) if total else 0,
        },
        "group_summary": group_summary,
        "cases": cases,
        "training_focus": "Teach MIM to select response mode before answering: recommendation, explanation, demonstration, consultative discovery, or problem analysis.",
    }
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "MIM_DURABILITY_SMOKE_V2.latest.json"
    md_path = out_dir / "MIM_DURABILITY_SMOKE_V2.latest.md"
    json_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(packet, md_path)
    print(json_path)
    print(md_path)
    return 0 if passed == total else 2


if __name__ == "__main__":
    raise SystemExit(main())
