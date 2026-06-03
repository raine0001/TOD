"""Run a focused MIM intent reinforcement round.

This smoke reinforces the lesson from the "what do you need from Dave?" fix:
short conversational prompts must be interpreted by intent and context, not
answered as generic status or raw runtime state.
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


CASES = [
    {
        "id": "dave_needed_direct",
        "prompt": "What do you need from Dave?",
        "expected": ("dave", "need", "next"),
        "reject": ("one concrete request", "ask for status"),
    },
    {
        "id": "training_blocker",
        "prompt": "Any blockers?",
        "expected": ("blocker", "next", "dave"),
        "reject": ("got it:", "ask me about"),
    },
    {
        "id": "stuck_analysis",
        "prompt": "Are you stuck?",
        "expected": ("problem", "next", "dave"),
        "reject": ("runtime health is stable", "microphone idle"),
    },
    {
        "id": "priority_intent",
        "prompt": "What should we work on next?",
        "expected": ("recommend", "because", "next"),
        "reject": ("i can answer that directly", "ask for status"),
    },
    {
        "id": "value_intent",
        "prompt": "What would create the most value?",
        "expected": ("value", "risk", "next"),
        "reject": ("i can answer that directly", "ask for status"),
    },
    {
        "id": "typo_priority",
        "prompt": "what shoud we werk on next",
        "expected": ("next", "recommend", "because"),
        "reject": ("provide the details", "ask me about"),
    },
    {
        "id": "training_status",
        "prompt": "how is training going MIM?",
        "expected": ("training", "mim", "tod", "blocker"),
        "reject": ("active objective:", "task "),
    },
    {
        "id": "more_training",
        "prompt": "tell me more about your training MIM",
        "expected": ("training", "mim", "tod", "next"),
        "reject": ("i can answer that directly", "ask for status"),
    },
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
            "test": "mim_intent_reinforcement_round",
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


def has_all(reply: str, terms: tuple[str, ...]) -> bool:
    lowered = reply.lower()
    return all(term in lowered for term in terms)


def has_none(reply: str, terms: tuple[str, ...]) -> bool:
    lowered = reply.lower()
    return not any(term in lowered for term in terms)


def no_raw_runtime_language(reply: str) -> bool:
    patterns = (
        r"\brequest[_ -]?id\b",
        r"\bobjective-\d+\b",
        r"\btask\s+\d{3,}\b",
        r"\blifecycle\b",
        r"\bpacket\b",
        r"\bGET\s+/",
    )
    return not any(re.search(pattern, reply, flags=re.IGNORECASE) for pattern in patterns)


def evaluate(case: dict[str, Any], reply: str) -> dict[str, Any]:
    checks = {
        "expected_terms_present": has_all(reply, tuple(case["expected"])),
        "bad_fallback_absent": has_none(reply, tuple(case["reject"])),
        "plain_enough": len(reply) >= 100,
        "no_raw_runtime_language": no_raw_runtime_language(reply),
    }
    return {
        "id": case["id"],
        "prompt": case["prompt"],
        "passed": all(checks.values()),
        "checks": checks,
        "reply_length": len(reply),
        "reply_excerpt": reply[:500],
    }


def write_markdown(packet: dict[str, Any], path: Path) -> None:
    summary = packet["summary"]
    lines = [
        "# MIM Intent Reinforcement Round",
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
        "## Failed Cases",
        "",
    ]
    failed = [case for case in packet["cases"] if not case.get("passed")]
    if not failed:
        lines.append("- None.")
    else:
        for case in failed:
            missing = [key for key, value in case["checks"].items() if not value]
            lines.append(f"- {case['prompt']}: missing {', '.join(missing)}.")
    lines.extend(["", "## Training Lesson", "", packet["training_lesson"]])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://192.168.1.120:18001")
    parser.add_argument("--out-dir", default=str(OUT_ROOT))
    args = parser.parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    cases: list[dict[str, Any]] = []
    for case in CASES:
        try:
            reply = post_gateway(args.base_url, str(case["prompt"]))
            cases.append(evaluate(case, reply))
        except Exception as exc:
            cases.append(
                {
                    "id": case["id"],
                    "prompt": case["prompt"],
                    "passed": False,
                    "error": " ".join(str(exc).split())[:300],
                    "checks": {"live_eval_available": False},
                }
            )
    passed = sum(1 for case in cases if case.get("passed"))
    packet = {
        "packet_type": "mim-intent-reinforcement-round-v1",
        "objective_id": "MIM-CONVERSATIONAL-INTENT-REINFORCEMENT-V1",
        "generated_at": utc_now(),
        "status": "passed" if passed == len(cases) else "failed_needs_more_intent_training",
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
        },
        "cases": cases,
        "training_lesson": (
            "MIM must infer the operator's intent from short conversational prompts before answering. "
            "When Dave asks what is needed, what is blocked, what is next, or whether MIM/TOD are stuck, "
            "the reply must name the situation, the next action, and whether Dave is needed."
        ),
    }
    json_path = out_dir / "MIM_INTENT_REINFORCEMENT_ROUND.latest.json"
    md_path = out_dir / "MIM_INTENT_REINFORCEMENT_ROUND.latest.md"
    json_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(packet, md_path)
    print(json_path)
    print(md_path)
    return 0 if packet["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
