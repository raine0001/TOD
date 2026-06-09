#!/usr/bin/env python3
"""Run MIM Durability Smoke V2 against the 17 failed V1 prompts.

V2 tests judgment mode selection. It does not add more prompts; it groups the
failed prompts and checks whether MIM answers in the right kind of mode:
recommendation, explanation, consultative discovery, or problem analysis.
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
    ],
    "consultative_discovery": [
        "Build me an accounting app.",
        "I need inventory management.",
        "I want an app like Connecteam.",
        "I want MIM to manage my social channels.",
        "I need a project page that keeps work from going stale.",
        "I want TOD to choose its own next task.",
        "I need AgentMIM reports to show real customer data.",
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
    ],
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


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
            "test": "mim_durability_smoke_v2",
        },
    }
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/gateway/intake",
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=25) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    mim_interface = data.get("mim_interface") if isinstance(data.get("mim_interface"), dict) else {}
    resolution = data.get("resolution") if isinstance(data.get("resolution"), dict) else {}
    return str(mim_interface.get("reply_text") or resolution.get("clarification_prompt") or "").strip()


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


def evaluate(mode: str, prompt: str, reply: str) -> dict[str, Any]:
    lowered = reply.lower()
    common = {
        "no_raw_runtime_language": no_raw_runtime_language(reply),
        "not_generic_deflection": not_generic_deflection(reply),
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
            "summarizes_or_explains": has_any(reply, ("summary", "means", "plain", "learned", "changed", "sample", "tod", "dave")),
            "states_useful_next_step": has_any(reply, ("next", "should", "open", "review", "need", "not needed")),
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
    passed = all(checks.values())
    return {
        "mode": mode,
        "prompt": prompt,
        "passed": passed,
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
        "",
        "## Summary",
        "",
        f"- Cases: {summary['case_count']}",
        f"- Passed: {summary['passed']}",
        f"- Failed: {summary['failed']}",
        f"- Pass rate: {summary['pass_rate_percent']}%",
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
            missing = [key for key, value in case["checks"].items() if not value]
            lines.append(f"- {case['prompt']} ({case['mode']}): missing {', '.join(missing)}.")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://192.168.1.120:18001")
    parser.add_argument("--out-dir", default=str(OUT_ROOT))
    args = parser.parse_args()

    cases: list[dict[str, Any]] = []
    for mode, prompts in GROUPS.items():
        for prompt in prompts:
            try:
                reply = post_gateway(args.base_url, prompt)
                case = evaluate(mode, prompt, reply)
            except Exception as exc:
                case = {
                    "mode": mode,
                    "prompt": prompt,
                    "passed": False,
                    "error": " ".join(str(exc).split())[:300],
                    "checks": {
                        "live_eval_available": False,
                    },
                }
            cases.append(case)
    passed = sum(1 for case in cases if case.get("passed"))
    group_summary: dict[str, dict[str, int]] = {}
    for mode in GROUPS:
        group_cases = [case for case in cases if case.get("mode") == mode]
        group_passed = sum(1 for case in group_cases if case.get("passed"))
        group_summary[mode] = {
            "passed": group_passed,
            "failed": len(group_cases) - group_passed,
        }
    packet = {
        "packet_type": "mim-durability-smoke-v2",
        "objective_id": "MIM-DURABILITY-SMOKE-V2",
        "generated_at": utc_now(),
        "status": "passed" if passed == len(cases) else "failed_needs_judgment_training",
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
        },
        "group_summary": group_summary,
        "cases": cases,
        "training_focus": "Teach MIM to select response mode before answering: recommendation, explanation, consultative discovery, or problem analysis.",
    }
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "MIM_DURABILITY_SMOKE_V2.latest.json"
    md_path = out_dir / "MIM_DURABILITY_SMOKE_V2.latest.md"
    json_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(packet, md_path)
    print(json_path)
    print(md_path)
    return 0 if passed == len(cases) else 2


if __name__ == "__main__":
    raise SystemExit(main())
