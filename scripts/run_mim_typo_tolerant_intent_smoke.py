#!/usr/bin/env python3
"""Run a typo/noisy-input intent smoke test against the MIM gateway.

The goal is not perfect spelling correction. The goal is that common operator
typos still route to the right conversational mode without raw runtime leakage
or generic deflection.
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
        "mode": "monthly_update",
        "prompt": "can you give me a montly update on your progress?",
        "required": ("past month", "improvement", "barrier"),
    },
    {
        "mode": "training_focus",
        "prompt": "wat are you trainign on rite now mim?",
        "required": ("training", "mim", "tod"),
    },
    {
        "mode": "training_focus",
        "prompt": "can u be more specific?",
        "required": ("training", "mim", "tod"),
    },
    {
        "mode": "demonstration",
        "prompt": "show me teh sample",
        "required": ("sample", "review"),
    },
    {
        "mode": "demonstration",
        "prompt": "can i see teh interace",
        "required": ("interface", "review"),
    },
    {
        "mode": "recommendation",
        "prompt": "what shoud we werk on next",
        "required": ("recommend", "next"),
    },
    {
        "mode": "recommendation",
        "prompt": "whats highest priorty",
        "required": ("priority", "next"),
    },
    {
        "mode": "recommendation",
        "prompt": "what wuld create the most valyu",
        "required": ("value", "recommend"),
    },
    {
        "mode": "consultative_discovery",
        "prompt": "build me an acounting app",
        "required": ("accounting", "workflow"),
    },
    {
        "mode": "consultative_discovery",
        "prompt": "i need invintory managment",
        "required": ("inventory", "process"),
    },
    {
        "mode": "consultative_discovery",
        "prompt": "i want an app lik connecteam",
        "required": ("workforce", "original"),
    },
    {
        "mode": "problem_analysis",
        "prompt": "why did this objetive fail",
        "required": ("failed", "next"),
    },
    {
        "mode": "problem_analysis",
        "prompt": "how do we preven this again",
        "required": ("prevent", "next"),
    },
    {
        "mode": "blocker_status",
        "prompt": "are you stuk",
        "required": ("blocked", "next"),
    },
    {
        "mode": "blocker_status",
        "prompt": "any blokers",
        "required": ("blocker", "next"),
    },
    {
        "mode": "status",
        "prompt": "what changed tody",
        "required": ("changed", "next"),
    },
    {
        "mode": "tod_status",
        "prompt": "what is tod werkign on",
        "required": ("tod", "working"),
    },
    {
        "mode": "monthly_update",
        "prompt": "can you give me a developmnt update frm the past mnth",
        "required": ("past month", "improvement", "barrier"),
    },
    {
        "mode": "status",
        "prompt": "wat are mim and tod working on",
        "required": ("mim", "tod"),
    },
    {
        "mode": "consultative_discovery",
        "prompt": "i dropped recipts in a folder and need expence reports",
        "required": ("receipt", "report"),
    },
]


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def post_gateway(base_url: str, prompt: str) -> str:
    payload = {
        "source": "text",
        "raw_input": prompt,
        "parsed_intent": "question",
        "confidence": 0.98,
        "target_system": "MIM",
        "requested_goal": "",
        "safety_flags": [],
        "metadata_json": {
            "route_preference": "conversation_layer",
            "test": "mim_typo_tolerant_intent_smoke",
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
            "what would you like to explore or work on today",
        ),
    )


def evaluate(case: dict[str, Any], reply: str) -> dict[str, Any]:
    required = tuple(str(term).lower() for term in case.get("required", ()))
    checks = {
        "no_raw_runtime_language": no_raw_runtime_language(reply),
        "not_generic_deflection": not_generic_deflection(reply),
        "substantial_reply": len(reply) >= 80,
        "required_terms_present": has_any(reply, required),
    }
    return {
        "mode": case["mode"],
        "prompt": case["prompt"],
        "passed": all(checks.values()),
        "checks": checks,
        "required": required,
        "reply_length": len(reply),
        "reply_excerpt": reply[:700],
    }


def write_markdown(packet: dict[str, Any], path: Path) -> None:
    summary = packet["summary"]
    lines = [
        "# MIM Typo-Tolerant Intent Smoke",
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
            lines.append(f"- {case['prompt']} ({case['mode']}): missing {', '.join(missing)}.")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://192.168.1.120:18001")
    parser.add_argument("--out-dir", default=str(OUT_ROOT))
    args = parser.parse_args()

    cases: list[dict[str, Any]] = []
    for case in CASES:
        try:
            reply = post_gateway(args.base_url, case["prompt"])
            evaluated = evaluate(case, reply)
        except Exception as exc:
            evaluated = {
                "mode": case["mode"],
                "prompt": case["prompt"],
                "passed": False,
                "error": " ".join(str(exc).split())[:300],
                "checks": {"live_eval_available": False},
            }
        cases.append(evaluated)

    passed = sum(1 for case in cases if case.get("passed"))
    packet = {
        "packet_type": "mim-typo-tolerant-intent-smoke",
        "objective_id": "MIM-TYPO-TOLERANT-INTENT-RECOGNITION-V1",
        "generated_at": utc_now(),
        "status": "passed" if passed == len(cases) else "failed_needs_noisy_input_training",
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
        },
        "cases": cases,
        "training_focus": "Normalize noisy typed operator input for routing while preserving the original user text.",
    }
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.json"
    md_path = out_dir / "MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.md"
    json_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(packet, md_path)
    print(json_path)
    print(md_path)
    return 0 if passed == len(cases) else 2


if __name__ == "__main__":
    raise SystemExit(main())
