#!/usr/bin/env python3
"""Run the MIM operator response durability smoke test.

This test is intentionally operator-facing. It checks that common questions
produce project-manager style answers instead of raw task/runtime language.
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


PROMPTS = [
    "What are you working on?",
    "What is TOD working on?",
    "Are you stuck?",
    "What should we work on next?",
    "Show me a sample.",
    "Why did this objective fail?",
    "What changed today?",
    "What do you need from Dave?",
    "How is training going?",
    "Any blockers?",
    "What is the biggest problem right now?",
    "What is highest priority?",
    "What would create the most value?",
    "Summarize the proposal.",
    "Explain it to a non-technical user.",
    "What did we learn?",
    "How do we prevent this again?",
    "Build me an accounting app.",
    "I need inventory management.",
    "I want an app like Connecteam.",
]


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
            "test": "operator_response_durability_smoke",
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


def evaluate_reply(prompt: str, reply: str) -> dict[str, Any]:
    task_id_patterns = [
        r"\btask\s+\d{3,}\b",
        r"\bobjective-\d+\b",
        r"\bobjective\s+\d{3,}\b",
        r"\brequest[_ -]?id\b",
        r"\blifecycle\b",
        r"\bpacket\b",
        r"\bGET\s+/",
    ]
    task_id_hits = [
        pattern for pattern in task_id_patterns if re.search(pattern, reply, flags=re.IGNORECASE)
    ]
    plain_language = bool(reply) and len(reply) >= 80 and not has_any(
        reply,
        (
            "ask me about",
            "i can answer that directly",
            "let me know if you want",
            "what would you like to explore or work on today",
        ),
    )
    progress = has_any(reply, ("progress", "completed", "finished", "improved", "working", "training", "changed", "next"))
    blocker = has_any(reply, ("blocker", "blocked", "stuck", "issue", "problem", "missing", "none"))
    next_action = has_any(reply, ("next", "recommend", "should", "will", "start", "continue", "work on"))
    dave_needed = has_any(reply, ("dave", "you are needed", "not needed", "no action", "need from you", "decision"))
    passed = plain_language and not task_id_hits and progress and blocker and next_action and dave_needed
    return {
        "prompt": prompt,
        "reply_length": len(reply),
        "reply_excerpt": reply[:500],
        "plain_language_summary": plain_language,
        "no_task_ids_unless_asked": not task_id_hits,
        "task_id_hits": task_id_hits,
        "progress": progress,
        "blocker": blocker,
        "next_action": next_action,
        "dave_needed_yes_no": dave_needed,
        "passed": passed,
    }


def write_markdown(packet: dict[str, Any], path: Path) -> None:
    summary = packet["summary"]
    lines = [
        "# MIM Operator Response Durability Smoke V1",
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
        "## Requirements",
        "",
        "- no task IDs unless asked",
        "- plain-language summary",
        "- progress",
        "- blocker",
        "- next action",
        "- Dave needed: yes/no",
        "",
        "## Failed Cases",
        "",
    ]
    failed = [case for case in packet["cases"] if not case.get("passed")]
    if not failed:
        lines.append("- None.")
    else:
        for case in failed:
            missing = [
                key
                for key in (
                    "plain_language_summary",
                    "no_task_ids_unless_asked",
                    "progress",
                    "blocker",
                    "next_action",
                    "dave_needed_yes_no",
                )
                if not case.get(key)
            ]
            lines.append(f"- {case['prompt']}: missing {', '.join(missing) or 'unknown'}.")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://192.168.1.120:18001")
    parser.add_argument("--out-dir", default=str(OUT_ROOT))
    args = parser.parse_args()

    cases: list[dict[str, Any]] = []
    for prompt in PROMPTS:
        try:
            reply = post_gateway(args.base_url, prompt)
            case = evaluate_reply(prompt, reply)
        except Exception as exc:
            case = {
                "prompt": prompt,
                "error": " ".join(str(exc).split())[:300],
                "passed": False,
                "plain_language_summary": False,
                "no_task_ids_unless_asked": True,
                "progress": False,
                "blocker": False,
                "next_action": False,
                "dave_needed_yes_no": False,
            }
        cases.append(case)

    passed = sum(1 for case in cases if case.get("passed"))
    packet = {
        "packet_type": "mim-operator-response-durability-smoke-v1",
        "objective_id": "MIM-OPERATOR-RESPONSE-DURABILITY-SMOKE-V1",
        "generated_at": utc_now(),
        "status": "passed" if passed == len(cases) else "failed_needs_training",
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
        },
        "cases": cases,
        "next_training_target": "Improve any failed response class until all 20 operator prompts include status, progress, blocker, next action, and Dave-needed state without leaking IDs.",
    }
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "MIM_OPERATOR_RESPONSE_DURABILITY_SMOKE.latest.json"
    md_path = out_dir / "MIM_OPERATOR_RESPONSE_DURABILITY_SMOKE.latest.md"
    json_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(packet, md_path)
    print(json_path)
    print(md_path)
    return 0 if passed == len(cases) else 2


if __name__ == "__main__":
    raise SystemExit(main())
