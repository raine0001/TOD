from __future__ import annotations

import argparse
import json
import random
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SUITE = REPO_ROOT / "tod" / "conversation_eval" / "public_mim_general_conversation_suite_v1.json"
DEFAULT_OUTPUT = REPO_ROOT / "shared_state" / "conversation_eval" / "public_mim_general_conversation_smoke.latest.json"
DEFAULT_MARKDOWN_OUTPUT = REPO_ROOT / "runtime_remote_training" / "MIM_PUBLIC_GENERAL_CONVERSATION_SMOKE.latest.md"


BAD_SUBSTRINGS = {
    "channel_deflection": [
        "this is the mim channel",
        "focused on planning, creativity, and broader thinking",
    ],
    "operator_contract_leak": [
        "recommended action:",
        "expected evidence:",
        "aging rule:",
        "dave needed:",
    ],
    "old_france_clarifier": [
        "could you clarify what specific topic or context",
    ],
}


SPANISH_MARKERS = {
    "hola",
    "estoy",
    "puedo",
    "puedes",
    "claro",
    "conversar",
    "explicar",
    "quieres",
    "gustaria",
    "mim es",
}


def _load_suite(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _post_message(base_url: str, session_key: str, message: str, timeout: int) -> str:
    payload = json.dumps(
        {"message": message, "mode": "mim", "session_key": session_key},
        ensure_ascii=False,
    ).encode("utf-8")
    request = urllib.request.Request(
        base_url.rstrip("/") + "/public/chat/message",
        data=payload,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.loads(response.read().decode("utf-8"))
    return str((data.get("reply") or {}).get("content") or "").strip()


def _looks_spanish(text: str) -> bool:
    lowered = text.lower()
    return any(marker in lowered for marker in SPANISH_MARKERS)


def _score_reply(card: dict[str, Any], turn: str, reply: str, turn_index: int) -> list[str]:
    failures: list[str] = []
    lowered = reply.lower()
    for tag, snippets in BAD_SUBSTRINGS.items():
        if any(snippet in lowered for snippet in snippets):
            failures.append(tag)
    if len(reply.split()) > 170 and "shorter" not in turn.lower() and "explain" not in turn.lower():
        failures.append("overlong_public_reply")
    if "?" in reply and any(token in turn.lower() for token in ("what day", "what time", "what are you", "who are you", "how are you")):
        if "what would you like" in lowered or "could you clarify" in lowered:
            failures.append("unnecessary_clarification")
    if "france" in turn.lower():
        if "france" not in lowered and "french" not in lowered:
            failures.append("lost_location_followup")
        if "clarify" in lowered:
            failures.append("unnecessary_clarification")
    if any(token in turn.lower() for token in ("como", "estas", "puedes", "explicame", "quiero")):
        if not _looks_spanish(reply):
            failures.append("language_mismatch_spanish")
    if turn_index > 0 and any(token in turn.lower() for token in ("that", "it", "what about", "how is that", "so why")):
        if "clarify" in lowered or "specific topic" in lowered:
            failures.append("lost_followup_context")
    return failures


def _select_cards(cards: list[dict[str, Any]], count: int, seed: int, sweep: bool) -> list[dict[str, Any]]:
    if sweep:
        return cards[:count]
    rng = random.Random(seed)
    if count >= len(cards):
        selected = list(cards)
        rng.shuffle(selected)
        return selected
    return rng.sample(cards, count)


def run_smoke(
    *,
    base_url: str,
    suite_path: Path,
    output_path: Path,
    count: int,
    seed: int,
    timeout: int,
    sweep: bool,
    delay_seconds: float,
    markdown_output_path: Path | None,
) -> dict[str, Any]:
    suite = _load_suite(suite_path)
    cards = _select_cards(list(suite["scenario_cards"]), count, seed, sweep)
    run_id = datetime.now(timezone.utc).strftime("public-mim-smoke-%Y%m%dT%H%M%SZ")
    runs: list[dict[str, Any]] = []
    failure_count = 0
    for index, card in enumerate(cards, start=1):
        session_key = f"{run_id}-{index:03d}"
        turns = [str(turn) for turn in card.get("user_turns") or []]
        turn_results = []
        card_failures: list[str] = []
        for turn_index, turn in enumerate(turns):
            try:
                reply = _post_message(base_url, session_key, turn, timeout)
                failures = _score_reply(card, turn, reply, turn_index)
            except (OSError, urllib.error.HTTPError, ValueError) as exc:
                reply = ""
                failures = [f"request_error:{type(exc).__name__}"]
            card_failures.extend(failures)
            turn_results.append({"turn": turn, "reply": reply, "failures": failures})
            if delay_seconds:
                time.sleep(delay_seconds)
        if card_failures:
            failure_count += 1
        runs.append(
            {
                "scenario_id": card.get("id"),
                "bucket": card.get("bucket"),
                "turns": turn_results,
                "passed": not card_failures,
                "failures": sorted(set(card_failures)),
            }
        )
    summary = {
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "base_url": base_url,
        "suite_path": str(suite_path),
        "scenario_count": len(runs),
        "passed_count": len(runs) - failure_count,
        "failure_count": failure_count,
        "pass_rate": round((len(runs) - failure_count) / max(1, len(runs)), 4),
    }
    report = {"summary": summary, "runs": runs}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if markdown_output_path is not None:
        markdown_output_path.parent.mkdir(parents=True, exist_ok=True)
        failing = [item for item in runs if not item["passed"]]
        lines = [
            "# MIM Public General Conversation Smoke",
            "",
            f"- Generated: {summary['generated_at']}",
            f"- Base URL: {base_url}",
            f"- Scenarios: {summary['scenario_count']}",
            f"- Passed: {summary['passed_count']}",
            f"- Failed: {summary['failure_count']}",
            f"- Pass rate: {summary['pass_rate']}",
            "",
            "## Coverage",
        ]
        buckets: dict[str, int] = {}
        for item in runs:
            bucket = str(item.get("bucket") or "unknown")
            buckets[bucket] = buckets.get(bucket, 0) + 1
        for bucket, bucket_count in sorted(buckets.items()):
            lines.append(f"- {bucket}: {bucket_count}")
        lines.extend(["", "## Failures"])
        if failing:
            for item in failing[:20]:
                lines.append(f"- {item['scenario_id']}: {', '.join(item['failures'])}")
        else:
            lines.append("- none")
        markdown_output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:18001")
    parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--markdown-output", default=str(DEFAULT_MARKDOWN_OUTPUT))
    parser.add_argument("--count", type=int, default=50)
    parser.add_argument("--seed", type=int, default=20260612)
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--sweep", action="store_true")
    parser.add_argument("--delay-seconds", type=float, default=0.0)
    args = parser.parse_args()
    report = run_smoke(
        base_url=args.base_url,
        suite_path=Path(args.suite),
        output_path=Path(args.output),
        count=args.count,
        seed=args.seed,
        timeout=args.timeout,
        sweep=args.sweep,
        delay_seconds=args.delay_seconds,
        markdown_output_path=Path(args.markdown_output) if args.markdown_output else None,
    )
    print(json.dumps(report["summary"], indent=2))


if __name__ == "__main__":
    main()
