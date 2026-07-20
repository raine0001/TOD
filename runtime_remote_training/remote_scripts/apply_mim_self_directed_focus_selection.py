from pathlib import Path
import subprocess

ROOT = Path("/home/testpilot/mim")
GATEWAY = ROOT / "core" / "routers" / "gateway.py"
COGNITIVE = ROOT / "core" / "mim_cognitive_entrypoint.py"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise RuntimeError(f"missing patch anchor: {label}")
    return text.replace(old, new, 1)


def main() -> None:
    text = GATEWAY.read_text(encoding="utf-8")
    backup_path = GATEWAY.with_suffix(".py.self_directed_focus_selection.bak")
    backup_path.write_text(text, encoding="utf-8")

    helper = '''

def _is_self_directed_focus_query(normalized_query: str) -> bool:
    query = str(normalized_query or "").strip().lower()
    if not query:
        return False
    actor_grounded = any(token in query for token in {"mim", "you", "your", "yourself"})
    if not actor_grounded:
        return False
    asks_for_choice = any(
        phrase in query
        for phrase in {
            "what would you like",
            "what do you want",
            "what would you choose",
            "what training would you choose",
            "which training would you choose",
            "what should you choose",
            "what would you focus",
            "what should you focus",
            "what would you study",
            "what should you study",
        }
    )
    asks_for_training_focus = any(
        token in query
        for token in {
            "focus training",
            "training focus",
            "focus on training",
            "focus your training",
            "focus to train",
            "train next",
            "training would you",
            "learn today",
            "learn next",
            "improve next",
            "study next",
            "work on or learn",
            "work on today",
        }
    )
    return asks_for_choice and asks_for_training_focus
'''
    if "def _is_self_directed_focus_query(" not in text:
        text = replace_once(
            text,
            "\n\ndef _should_defer_conversation_purpose_to_operator_context(",
            helper + "\n\ndef _should_defer_conversation_purpose_to_operator_context(",
            "insert self-directed focus detector",
        )

    text = replace_once(
        text,
        "    if _is_self_evolution_next_work_query(query):\n        return True\n",
        "    if _is_self_evolution_next_work_query(query) or _is_self_directed_focus_query(query):\n        return True\n",
        "defer self-directed focus before purpose engine",
    )

    text = replace_once(
        text,
        "def _self_evolution_next_work_response(context: dict[str, object]) -> str:\n",
        "def _self_evolution_next_work_response(\n    context: dict[str, object],\n    *,\n    self_directed_focus: bool = False,\n) -> str:\n",
        "self-evolution response signature",
    )

    focus_block = '''    if self_directed_focus:
        primary = focus
        if primary.strip().lower() in {"natural-language development", "intent recognition"} and next_work:
            primary = next_work
        if "newest improvement recommendation" in primary.lower():
            primary = "turning the current improvement recommendation into one validated behavior change"
        secondary = "TOD choosing and completing the next bounded task without waiting for Codex"
        if "tod" in (summary + " " + language_summary + " " + snapshot_summary).lower():
            secondary = "TOD independent resolution: inspect, change behavior, validate, and publish evidence"
        reason_one = why or language_summary or snapshot_summary
        if not reason_one:
            reason_one = "it is the current evidence-backed training pressure from the self-evolution briefing"
        reason_two = (
            "it reduces repeated stalls where operator intent is translated repeatedly and TOD waits for a more exact packet"
        )
        parts = [
            f"I would focus first on {primary.rstrip('.')}.",
            f"Second, I would focus on {secondary}.",
            "",
            f"Those outrank broader training because {reason_one.rstrip('.')}.",
            f"They also create more autonomy than another general conversation drill because {reason_two}.",
        ]
        if progress:
            parts.extend(["", f"Current evidence: {progress.rstrip('.')}."])
        if next_step:
            parts.extend(["", f"Next proof I would want: {next_step.rstrip('.')}."])
        return "\\n".join(parts).strip()

'''
    if "if self_directed_focus:" not in text:
        text = replace_once(
            text,
            '    readable_parts = [\n        "Yes. The next thing I would work on is improving how I understand and carry operator intent across normal conversation.",\n',
            focus_block
            + '    readable_parts = [\n        "Yes. The next thing I would work on is improving how I understand and carry operator intent across normal conversation.",\n',
            "self-directed focus response branch",
        )
    else:
        text = text.replace(
            '        reason_two = (\n            "it reduces repeated stalls where MIM has to translate intent and TOD waits for a more exact packet"\n        )\n',
            '        if "newest improvement recommendation" in primary.lower():\n'
            '            primary = "turning the current improvement recommendation into one validated behavior change"\n'
            '        reason_two = (\n'
            '            "it reduces repeated stalls where operator intent is translated repeatedly and TOD waits for a more exact packet"\n'
            '        )\n',
        )

    text = replace_once(
        text,
        "    if _is_self_evolution_next_work_query(normalized_query):\n        next_work_response = _self_evolution_next_work_response(context)\n",
        "    self_directed_focus = _is_self_directed_focus_query(normalized_query)\n    if _is_self_evolution_next_work_query(normalized_query) or self_directed_focus:\n        next_work_response = _self_evolution_next_work_response(\n            context,\n            self_directed_focus=self_directed_focus,\n        )\n",
        "conversation response self-directed branch",
    )

    text = replace_once(
        text,
        '        if next_work_response:\n            return next_work_response\n        return (\n            "Next I would refresh the current self-evolution state, pick one communication-focused improvement task, "\n',
        '        if next_work_response:\n            return next_work_response\n        if self_directed_focus:\n            return (\n                "I would focus on the highest-friction training gap that current evidence can prove, then validate it with a live prompt. "\n                "I should not ask you to choose unless the evidence is tied between two priorities."\n            )\n        return (\n            "Next I would refresh the current self-evolution state, pick one communication-focused improvement task, "\n',
        "self-directed fallback",
    )

    text = replace_once(
        text,
        "            if _is_self_evolution_next_work_query(normalized_conversation_query):\n                self_evolution_briefing_result = await build_self_evolution_briefing(\n",
        "            if _is_self_evolution_next_work_query(\n                normalized_conversation_query\n            ) or _is_self_directed_focus_query(normalized_conversation_query):\n                self_evolution_briefing_result = await build_self_evolution_briefing(\n",
        "load self-evolution briefing for self-directed focus",
    )

    if '"self_directed_focus_selection": _is_self_directed_focus_query(' not in text:
        text = replace_once(
            text,
            '                "self_evolution_briefing": self_evolution_briefing,\n                "response_mode": str(metadata.get("response_mode") or "").strip().lower(),\n',
            '                "self_evolution_briefing": self_evolution_briefing,\n                "self_directed_focus_selection": _is_self_directed_focus_query(\n                    normalized_conversation_query\n                ),\n                "response_mode": str(metadata.get("response_mode") or "").strip().lower(),\n',
            "add response context flag",
        )

    text = replace_once(
        text,
        "    if _is_self_evolution_next_work_query(_normalize_conversation_query(user_input)):\n        deterministic_reply = build_deterministic_communication_reply(\n            user_input=user_input,\n            context=context,\n            fallback_reply=fallback_reply,\n        )\n        return {\n            \"reply_text\": str(deterministic_reply.reply_text or fallback_reply).strip(),\n            \"contract\": deterministic_reply.to_payload(),\n        }\n",
        "    normalized_user_input = _normalize_conversation_query(user_input)\n    if _is_self_directed_focus_query(normalized_user_input):\n        reply_text = _conversation_response(user_input, context=context)\n        return {\n            \"reply_text\": str(reply_text or fallback_reply).strip(),\n            \"contract\": {\n                \"reply_text\": str(reply_text or fallback_reply).strip(),\n                \"response_mode\": \"self_directed_focus\",\n                \"composer_mode\": \"deterministic_self_evolution_briefing\",\n                \"should_store_memory\": True,\n                \"memory_topics\": [\"mim_self_directed_focus\", \"self_evolution\"],\n                \"memory_people\": [],\n                \"memory_events\": [],\n                \"memory_experiences\": [],\n                \"suppress_operator_impact_contract\": True,\n                \"operator_contract_allowed\": False,\n            },\n        }\n    if _is_self_evolution_next_work_query(normalized_user_input):\n        deterministic_reply = build_deterministic_communication_reply(\n            user_input=user_input,\n            context=context,\n            fallback_reply=fallback_reply,\n        )\n        return {\n            \"reply_text\": str(deterministic_reply.reply_text or fallback_reply).strip(),\n            \"contract\": deterministic_reply.to_payload(),\n        }\n",
        "authoritative self-directed focus reply before deterministic composer",
    )

    GATEWAY.write_text(text, encoding="utf-8")

    cognitive_text = COGNITIVE.read_text(encoding="utf-8")
    cognitive_backup_path = COGNITIVE.with_suffix(".py.self_directed_focus_selection.bak")
    cognitive_backup_path.write_text(cognitive_text, encoding="utf-8")
    cognitive_helper = '''

def _is_self_directed_focus_query(text: str) -> bool:
    query = _normalize_text(text)
    if not query:
        return False
    if not any(token in query for token in ("mim", "you", "your", "yourself")):
        return False
    asks_for_choice = any(
        marker in query
        for marker in (
            "what would you like",
            "what do you want",
            "what would you choose",
            "what training would you choose",
            "which training would you choose",
            "what should you choose",
            "what would you focus",
            "what should you focus",
            "what would you study",
            "what should you study",
        )
    )
    asks_for_training_focus = any(
        marker in query
        for marker in (
            "focus training",
            "training focus",
            "focus on training",
            "focus your training",
            "focus to train",
            "train next",
            "training would you",
            "learn today",
            "learn next",
            "improve next",
            "study next",
            "work on or learn",
            "work on today",
        )
    )
    return asks_for_choice and asks_for_training_focus
'''
    if "def _is_self_directed_focus_query(" not in cognitive_text:
        cognitive_text = replace_once(
            cognitive_text,
            "\n\ndef _is_direct_fact_query(text: str) -> bool:\n",
            cognitive_helper + "\n\ndef _is_direct_fact_query(text: str) -> bool:\n",
            "insert cognitive self-directed focus detector",
        )
    cognitive_text = replace_once(
        cognitive_text,
        '    elif _is_direct_fact_query(prompt):\n        purpose_name = "direct_fact"\n        response_mode = "direct_answer"\n',
        '    elif _is_self_directed_focus_query(prompt):\n        purpose_name = "self_directed_focus"\n        response_mode = "self_directed_focus"\n        evidence_boundary = "runtime_training_evidence_required"\n    elif _is_direct_fact_query(prompt):\n        purpose_name = "direct_fact"\n        response_mode = "direct_answer"\n',
        "cognitive self-directed purpose branch",
    )
    cognitive_text = replace_once(
        cognitive_text,
        '    if response_mode in {"social_direct", "direct_answer", "grounded_bounded_action"}:\n',
        '    if response_mode in {"social_direct", "direct_answer", "grounded_bounded_action", "self_directed_focus"}:\n',
        "cognitive suppress operator contract for self-directed focus",
    )
    COGNITIVE.write_text(cognitive_text, encoding="utf-8")

    subprocess.run(["python3", "-m", "py_compile", str(GATEWAY), str(COGNITIVE)], cwd=str(ROOT), check=True)
    subprocess.run(["systemctl", "--user", "restart", "mim-mobile-web.service"], check=True)
    active = subprocess.run(
        ["systemctl", "--user", "is-active", "mim-mobile-web.service"],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        check=True,
    )
    print(active.stdout.strip())


if __name__ == "__main__":
    main()
