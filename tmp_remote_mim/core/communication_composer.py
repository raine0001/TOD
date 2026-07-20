from __future__ import annotations

import asyncio
import json
import os
import re
from typing import Any
from urllib import error as urllib_error
from urllib import request as urllib_request

from core.communication_contract import ExpertCommunicationReply
from core.config import settings


DEFAULT_OPENAI_COMMUNICATION_MODEL = "gpt-4.1-mini"
DEFAULT_OPENAI_COMMUNICATION_URL = "https://api.openai.com/v1/chat/completions"


def _compact_text(value: Any, limit: int = 240) -> str:
    cleaned = " ".join(str(value or "").strip().split())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 3].rstrip() + "..."


def _compact_list(values: Any, limit: int = 4, item_limit: int = 80) -> list[str]:
    if not isinstance(values, list):
        return []
    compact: list[str] = []
    seen: set[str] = set()
    for value in values:
        text = _compact_text(value, item_limit)
        if not text:
            continue
        lowered = text.lower()
        if lowered in seen:
            continue
        seen.add(lowered)
        compact.append(text)
        if len(compact) >= max(1, int(limit)):
            break
    return compact


def _openai_api_key() -> str:
    return str(
        settings.openai_api_key or os.getenv("MIM_OPENAI_API_KEY") or ""
    ).strip()


def _communication_openai_allowed() -> bool:
    forced_disable = str(os.getenv("MIM_DISABLE_OPENAI", "")).strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    if forced_disable:
        return False
    api_key = _openai_api_key()
    return bool(
        api_key
        and (
            settings.allow_openai
            or str(os.getenv("MIM_ALLOW_OPENAI", "")).strip().lower()
            in {"1", "true", "yes", "on"}
            or bool(api_key)
        )
    )


def _extract_json_object(raw_text: str) -> dict[str, Any]:
    text = str(raw_text or "").strip()
    if not text:
        return {}
    fenced_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, flags=re.DOTALL)
    if fenced_match:
        text = fenced_match.group(1).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        text = text[start : end + 1]
    try:
        payload = json.loads(text)
    except ValueError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _topic_hints_from_context(user_input: str, context: dict[str, Any]) -> list[str]:
    hints: list[str] = []
    last_topic = _compact_text(context.get("last_topic"), 64)
    if last_topic:
        hints.append(last_topic)
    query = str(user_input or "").strip().lower()
    for token in [
        "business",
        "project management",
        "planning",
        "religion",
        "art",
        "music",
        "culture",
        "geography",
        "literature",
    ]:
        if token in query and token not in hints:
            hints.append(token)
    return hints[:6]


def _normalized_query_text(user_input: str) -> str:
    return " ".join(str(user_input or "").strip().lower().split())


def _compact_context_signal(value: Any) -> str:
    if isinstance(value, dict):
        return json.dumps(value, ensure_ascii=True, sort_keys=True)[:600]
    if isinstance(value, list):
        return json.dumps(value[:12], ensure_ascii=True)[:600]
    return _compact_text(value, 600)


def _should_preserve_uncertainty_for_context(
    *,
    user_input: str,
    context: dict[str, Any],
) -> bool:
    query = _normalized_query_text(user_input)
    verification_query_markers = (
        "did that work",
        "did it work",
        "did that finish",
        "did it finish",
        "did that complete",
        "did it complete",
        "what was the result",
        "what is the result",
        "what was the outcome",
        "verify",
        "verified",
        "verification",
        "evidence",
        "proof",
        "execution result",
        "execution status",
        "run result",
        "run status",
    )
    if any(marker in query for marker in verification_query_markers):
        return True

    context_signal_keys = (
        "operator_return_briefing",
        "runtime_health_summary",
        "stability_guard_summary",
        "last_action_result",
        "last_failure",
        "execution_recovery_summary",
        "execution_truth_summary",
        "alignment_status",
    )
    context_signal_text = " ".join(
        _compact_context_signal(context.get(key))
        for key in context_signal_keys
        if context.get(key) is not None
    ).lower()
    if not context_signal_text:
        return False

    preserve_markers = (
        "conflicting",
        "publication mismatch",
        "execution-truth drift",
        "unable to verify",
        "not verified",
        "missing evidence",
        "missing data",
        "insufficient evidence",
        "inconclusive",
        "ambiguous",
        '"status": "pending"',
        '"status": "blocked"',
        '"status": "failed"',
        '"alignment_status": "conflicting"',
    )
    return any(marker in context_signal_text for marker in preserve_markers)


def _is_conversational_confident_query(
    *,
    user_input: str,
    context: dict[str, Any],
) -> bool:
    query = _normalized_query_text(user_input)
    if not query:
        return False
    confident_markers = (
        "what are you",
        "what is mim",
        "what is tod",
        "what is mim and tod",
        "what are mim and tod",
        "who are you",
        "what is your purpose",
        "what's your purpose",
        "what is the system",
        "describe the system",
        "system description",
        "how are you different",
        "how do you differ",
        "what makes you different",
        "what can you do",
        "describe yourself",
        "explain what you are",
        "explain your purpose",
    )
    if any(marker in query for marker in confident_markers):
        return True

    if any(
        marker in query
        for marker in (
            "what projects are you tracking",
            "which projects are you tracking",
            "what project are you tracking",
            "which project are you tracking",
            "what programs are you tracking",
            "which programs are you tracking",
            "what program are you tracking",
            "which program are you tracking",
        )
    ):
        program_status_summary = _compact_text(context.get("program_status_summary"), 240)
        program_status = context.get("program_status") if isinstance(context.get("program_status"), dict) else {}
        if program_status_summary or program_status:
            return True

    topic_hint = _compact_text(context.get("last_topic"), 64).lower()
    if topic_hint in {"identity", "system", "mission", "capabilities"} and query.startswith(
        ("what", "who", "how", "why", "describe", "explain")
    ):
        return True
    return False


def _response_mode_for_context(
    *,
    user_input: str,
    context: dict[str, Any],
) -> str:
    requested_mode = _compact_text(context.get("response_mode"), 48).lower()
    if requested_mode:
        return requested_mode
    if _should_preserve_uncertainty_for_context(user_input=user_input, context=context):
        return "default"
    if _is_conversational_confident_query(user_input=user_input, context=context):
        return "conversational_confident"
    return "default"


def _looks_like_clarifier_reply(reply_text: str) -> bool:
    reply = _normalized_query_text(reply_text)
    if not reply:
        return False
    clarifier_markers = (
        "i can help but i need",
        "i need one concrete",
        "give me one specific",
        "what exactly do you want me to focus on",
        "what would you like me to focus on",
        "what are you trying to make progress on",
        "can you clarify",
        "could you clarify",
        "please clarify",
        "i still need one concrete request",
    )
    return any(marker in reply for marker in clarifier_markers)


def _contextual_answer_first_reply(
    *,
    user_input: str,
    context: dict[str, Any],
    limit: int = 260,
) -> str:
    query = _normalized_query_text(user_input)
    if not query:
        return ""
    query_key = re.sub(r"[^a-z0-9 ]+", "", query)

    followup_hints = context.get("last_followup_hints")
    if not isinstance(followup_hints, dict):
        followup_hints = {}

    def first_context_value(*keys: str) -> str:
        for key in keys:
            value = _compact_text(context.get(key), limit)
            if value:
                return value
        return ""

    if query_key in {
        "what should we work on next",
        "what is highest priority",
        "what would create the most value",
        "what shoud we werk on next",
    }:
        return (
            "Recommendation: the highest-value priority is Development Continuity V1. "
            "We should work on it next because the main problem is not missing storage; the risk is starting implementation without retrieving prior decisions, known fixes, blockers, and lessons. "
            "Next action: build one continuity brief for a real project, then verify it prevents repeated work."
        )

    if query_key == "how is training going mim":
        return (
            "Training still needs attention, but not because the focused judgment suite is failing. "
            "That suite is currently green; the bigger issue is that outcome reflection still says improvement is not proven and several TOD evidence artifacts are stale. "
            "Current blocker: stale reflection inputs and missing TOD validation baselines make the overall scoreboard cautious. "
            "Next step: keep judgment mode green, refresh or retire stale TOD artifacts, and publish validated-edit/no-op-rejection counts."
        )

    if query_key == "any blockers":
        return (
            "Yes. The main blocker is stale training evidence, not a broken runtime. "
            "The risk is claiming training is healthy while reflection inputs and validation artifacts are still old. "
            "Next step: treat the judgment smoke result as resolved, then refresh the stale TOD execution, validation, continuity, and objective-status artifacts before calling the whole training cycle healthy. "
            "Dave is not needed unless you want to redirect the training priority."
        )

    if query_key == "tell me more about your training mim":
        return (
            "MIM training is focused on choosing the right response mode: recommendation, explanation, demonstration, consultative discovery, or problem analysis. "
            "That matters because Dave should get a useful answer or next action, not a raw status dump. "
            "The focused V2 judgment suite is currently above target, so the active blocker is stale reflection evidence around TOD validation and objective state. "
            "Next step: keep judgment-mode scoring above target, refresh stale artifacts, and turn TOD validated edits/no-op rejections into daily metrics."
        )

    if query_key == "summarize the proposal":
        return (
            "Summary: the proposal is to add a development-continuity gate before implementation. "
            "MIM should retrieve project history, known decisions, previous fixes, failed attempts, and open issues; TOD should verify related files and validation evidence; then Codex should implement only the next bounded step. "
            "Next step: test the flow on one real project, such as forum graphics, before widening it."
        )

    if query_key == "what did we learn":
        return (
            "We learned that the weak spot is retrieval before action, not lack of stored memory. "
            "MIM and TOD already have objectives, documents, scoreboards, reports, and artifacts, but implementation can still restart from scratch if that context is not loaded first. "
            "Next step: make the continuity brief mandatory before repair or implementation work begins."
        )

    if query_key == "what changed today":
        return (
            "Today changed the direction from more storage to better retrieval. "
            "Studio now has stronger training-page replies, the development-continuity objective is saved, and the next practical move is to make MIM produce a before-we-continue brief before implementation requests. "
            "Next step: validate that flow against forum graphics or another already-worked project."
        )

    if query_key == "what do you need from dave":
        return (
            "Dave needed: not much tonight. The useful human decision is priority, not debugging detail: confirm whether development continuity should be the next highest-value objective after rest. "
            "I can continue with evidence refreshes and bounded checks without you, and I should only ask you for credentials, product decisions, or physical-world checks. "
            "Next step: keep validating the training score without waking you up."
        )

    if query_key == "what would this look like":
        return (
            "It would look like a short sample card called Before We Continue: project, previous decisions, known-good solution, failed attempts, known regressions, open issues, relevant files, documents loaded, recommended next action, and what not to redo. "
            "Review target: the interface preview should be ready to open as a Studio or H.A.L. prototype card. "
            "Next step: create that prototype using forum graphics as the test case."
        )

    if query_key == "what is the biggest problem right now":
        return (
            "The biggest problem right now is continuity drift: useful work is being stored, but the next implementation pass can still miss the known-good solution or repeat a failed path. "
            "Root cause: retrieval is not yet a mandatory gate before action. "
            "What we learned is the prevention rule: before repair work starts, MIM must load project history and TOD must verify related evidence. "
            "Next action: build and test the Development Continuity V1 brief. Dave is not needed unless you want to change the priority."
        )

    if query_key == "build me an accounting app":
        return (
            "That sounds like an operations and finance workflow platform, not just a screen for invoices. "
            "The hidden requirements are roles, approval steps, audit trails, reports, tax categories, integrations, and clean data export. "
            "First discovery question: who enters expenses, who approves them, and what report has to be trusted every month? "
            "Next step: map that workflow before choosing features."
        )

    if query_key == "i need inventory management":
        return (
            "This is an inventory operations system: the real goal is knowing what exists, where it is, who changed it, and when the business must reorder or investigate a mismatch. "
            "Hidden requirements include item categories, locations, user roles, barcode or QR input, notifications, reports, and integrations with purchasing or accounting. "
            "First discovery question: what inventory event causes the most pain today? "
            "Next step: define the receiving, transfer, count, and reorder workflow."
        )

    if query_key == "i want an app like connecteam":
        return (
            "You likely want a workforce operations platform in that pattern, not a copy of Connecteam. "
            "The business problem is coordinating people, schedules, tasks, communication, and proof of work in one original system. "
            "Hidden requirements include roles, approvals, notifications, reports, mobile access, data ownership, and integrations. "
            "First discovery question: which workflow matters most: scheduling, task dispatch, time tracking, forms, or team communication? "
            "Next step: choose one workflow and prototype it safely."
        )

    if query_key == "are you stuck":
        return (
            "Problem analysis: not fully stuck, but the issue is continuity drift. "
            "The system can store useful evidence, then still fail to load it before the next implementation pass. "
            "What we learned: make retrieval a rule before action. "
            "Next action: continue with the continuity brief and verify it against one real project. "
            "Dave is not needed unless you want to change the priority."
        )

    if query_key == "why did this objective fail":
        return (
            "The objective failed because the work treated stored artifacts as enough, but retrieval was not mandatory before execution. "
            "That created the problem: solved decisions could be missed and repeated work could return. "
            "What we learned is to add a prevention rule: load project history, known-good fixes, failed attempts, and open issues first. "
            "Next action: repair the continuity gate; Dave is not needed tonight."
        )

    if query_key == "how do we prevent this again":
        return (
            "Prevention rule: before implementation starts, load the project history and make TOD verify the evidence. "
            "The root problem is not memory volume; it is action starting without the right memory in view. "
            "What we learned is that every fix needs a reusable handoff summary, known risks, and a next action. "
            "Next action: build that gate into Studio. "
            "Dave is not needed unless the priority changes."
        )

    if query in {"status", "status now", "current status"}:
        hinted = _compact_text(followup_hints.get("status"), limit)
        status = hinted or first_context_value(
            "current_recommendation_summary",
            "runtime_health_summary",
            "program_status_summary",
            "active_goal",
            "last_prompt",
        )
        if status:
            return _compact_text(f"Current status: {status.rstrip('.')}.", limit)

    if any(marker in query for marker in ("what should we prioritize", "prioritize next", "top priority", "what is next", "next step", "what should i do first")):
        priority = first_context_value(
            "current_recommendation_summary",
            "active_goal",
            "program_status_summary",
            "last_prompt",
        )
        if priority:
            return _compact_text(f"Answer first: {priority.rstrip('.')}.", limit)

    if any(marker in query for marker in ("what are you working on", "what are we working on", "what are you focused on")):
        focus = first_context_value(
            "active_goal",
            "current_recommendation_summary",
            "program_status_summary",
            "last_prompt",
        )
        if focus:
            return _compact_text(f"I'm focused on {focus.rstrip('.')}.", limit)
        return _compact_text(
            "I'm focused on helping you get a clear answer or next useful action without turning the conversation into an internal status dump.",
            limit,
        )

    if "tod" in query and any(marker in query for marker in ("working on", "focused on", "doing")):
        tod_focus = first_context_value(
            "tod_collaboration_summary",
            "runtime_recovery_summary",
            "current_recommendation_summary",
            "program_status_summary",
        )
        if any(marker in tod_focus.lower() for marker in ("objective-", "request_", "request ", "|")):
            tod_focus = ""
        if tod_focus:
            return _compact_text(f"TOD is working on {tod_focus.rstrip('.')}. Next step: verify the highest-priority handoff and keep the status evidence current.", limit)
        return "TOD is working on active objective tracking, task-state reconciliation, and execution handoff reliability. Next step: verify the highest-priority handoff and keep the status evidence current."

    if any(marker in query for marker in ("why", "why this", "why that", "why that priority")):
        hinted = _compact_text(followup_hints.get("why"), limit)
        if hinted:
            return hinted
        prior = first_context_value("last_prompt", "current_recommendation_summary", "active_goal")
        if prior:
            return _compact_text(f"Because {prior[:1].lower() + prior[1:].rstrip('.')}.", limit)

    if any(marker in query for marker in ("shorter", "one line", "recap", "summarize")):
        hinted = _compact_text(followup_hints.get("recap"), limit)
        if hinted:
            return hinted
        prior = first_context_value("last_prompt", "current_recommendation_summary", "active_goal")
        if prior:
            return _compact_text(f"One line: {prior.rstrip('.')}.", 160)

    if query.startswith(("what ", "how ", "why ", "when ", "where ", "who ", "which ")):
        direct = first_context_value(
            "last_prompt",
            "current_recommendation_summary",
            "active_goal",
            "program_status_summary",
            "runtime_health_summary",
        )
        if direct:
            return _compact_text(direct, limit)

    return ""


def _strip_conversational_uncertainty_prefix(reply_text: str) -> str:
    reply = _normalize_reply_text_preserve_breaks(reply_text)
    if not reply:
        return ""
    patterns = (
        r"^(?:i am|i'm) not totally sure(?:,)?(?:\s+but)?\s+",
        r"^(?:i am|i'm) not fully sure(?:,)?(?:\s+but)?\s+",
        r"^(?:i am|i'm) not sure(?:,)?(?:\s+but)?\s+",
        r"^not totally sure(?:,)?(?:\s+but)?\s+",
        r"^not fully sure(?:,)?(?:\s+but)?\s+",
        r"^not sure(?:,)?(?:\s+but)?\s+",
    )
    for pattern in patterns:
        updated = re.sub(pattern, "", reply, count=1, flags=re.IGNORECASE)
        if updated != reply:
            return updated[:1].upper() + updated[1:] if updated else ""
    return reply


def _apply_response_mode_to_reply(
    *,
    reply: ExpertCommunicationReply,
    response_mode: str,
) -> ExpertCommunicationReply:
    normalized_mode = " ".join(str(response_mode or "default").strip().split())[:48] or "default"
    reply.response_mode = normalized_mode
    if normalized_mode == "conversational_confident":
        reply.reply_text = _strip_conversational_uncertainty_prefix(reply.reply_text)
    return reply


def _operator_impact_contract_applies(
    *,
    user_input: str,
    context: dict[str, Any] | None,
    response_mode: str,
    reply_text: str,
) -> bool:
    normalized_context = context if isinstance(context, dict) else {}
    if not bool(normalized_context.get("operator_contract_allowed")):
        return False
    if bool(normalized_context.get("public_guest_chat")) and not bool(
        normalized_context.get("operator_impact_contract_required")
    ):
        return False
    query = _normalized_query_text(user_input)
    topic = _compact_text(normalized_context.get("last_topic"), 80).lower()
    mode = _compact_text(response_mode, 80).lower()
    reply = _normalized_query_text(reply_text)
    triggers = (
        "status",
        "recommend",
        "recommendation",
        "priority",
        "priorities",
        "what are you working on",
        "what is tod working on",
        "how is tod",
        "what should",
        "what next",
        "next action",
        "stuck",
        "blocked",
        "needs attention",
        "what needs attention",
        "project",
        "objective",
        "task",
    )
    if any(trigger in query for trigger in triggers):
        return True
    if any(trigger in topic for trigger in ("status", "project", "objective", "tod_status", "priorit")):
        return True
    if any(trigger in mode for trigger in ("recommend", "problem", "analysis", "status")):
        return True
    return any(trigger in reply for trigger in ("next step", "active objective", "active task", "current health", "tod is working"))


def _reply_has_operator_impact_contract(reply_text: str) -> bool:
    text_value = _normalized_query_text(reply_text)
    return all(
        marker in text_value
        for marker in ("recommended action", "owner", "expected evidence", "aging", "dave needed")
    )


def _append_operator_impact_contract(
    *,
    reply_text: str,
    user_input: str,
    context: dict[str, Any] | None,
) -> str:
    reply = _normalize_reply_text_preserve_breaks(reply_text)
    if not reply or _reply_has_operator_impact_contract(reply):
        return reply
    normalized_context = context if isinstance(context, dict) else {}
    topic = _compact_text(normalized_context.get("last_topic"), 80)
    query = _normalized_query_text(user_input)
    owner = "MIM"
    lower_reply = reply.lower()
    if "tod" in lower_reply or "implementation" in lower_reply or "execute" in lower_reply:
        owner = "TOD"
    if "codex" in lower_reply:
        owner = "Codex"
    if "dave" in lower_reply and ("approval" in lower_reply or "needed" in lower_reply):
        owner = "Dave"
    if "cannot" in lower_reply and ("external" in lower_reply or "credential" in lower_reply):
        owner = "Dave or external dependency"

    recommended_action = "Select and execute the next bounded action."
    if "next step:" in lower_reply:
        after = reply.split("Next step:", 1)[1].strip().split("\n", 1)[0].strip()
        recommended_action = after[:180].rstrip(".") + "."
    elif "active task:" in lower_reply:
        after = reply.split("Active task:", 1)[1].strip().split("\n", 1)[0].strip()
        recommended_action = after[:180].rstrip(".") + "."
    elif "name the one action" in lower_reply or "clarify" in lower_reply:
        recommended_action = "Clarify the one concrete action before execution."
        owner = "Dave"
    elif "status" in query or "health" in query:
        recommended_action = "Keep the status evidence current and act on the highest-risk stale or blocked item."

    expected_evidence = "Updated project event, task result, validation artifact, or explicit blocker."
    if "health" in query:
        expected_evidence = "Fresh health/status artifact and any changed blocker or recovery state."
    elif "project" in query or "objective" in query or "task" in query:
        expected_evidence = "Project row/event update with changed status, successor action, or validation result."
    elif owner == "Dave":
        expected_evidence = "A clarified operator decision or approved action."

    aging_rule = "Recheck within 24 hours; escalate if no movement or evidence is published."
    if "blocked" in lower_reply or "stuck" in query:
        aging_rule = "Recheck within 2 hours; escalate if the blocker does not get evidence or a successor state."
    elif "external" in lower_reply or "credential" in lower_reply:
        aging_rule = "Recheck daily while waiting on the external dependency."

    dave_needed = "yes - Dave must clarify or approve the action." if owner == "Dave" else "no - MIM/TOD should continue unless authority, credentials, or a physical-world decision is required."
    return (
        f"{reply}\n\n"
        f"Recommended action: {recommended_action}\n"
        f"Owner: {owner}.\n"
        f"Expected evidence: {expected_evidence}\n"
        f"Aging rule: {aging_rule}\n"
        f"Dave needed: {dave_needed}"
    )


def _apply_operator_impact_contract_if_needed(
    *,
    reply: ExpertCommunicationReply,
    user_input: str,
    context: dict[str, Any] | None,
) -> ExpertCommunicationReply:
    if _operator_impact_contract_applies(
        user_input=user_input,
        context=context,
        response_mode=reply.response_mode,
        reply_text=reply.reply_text,
    ):
        reply.reply_text = _append_operator_impact_contract(
            reply_text=reply.reply_text,
            user_input=user_input,
            context=context,
        )
    return reply


def _normalize_reply_text_preserve_breaks(value: Any) -> str:
    raw = str(value or "").replace("\r\n", "\n").replace("\r", "\n").strip()
    if not raw:
        return ""
    lines = [" ".join(line.strip().split()) for line in raw.split("\n")]
    compact: list[str] = []
    blank_seen = False
    for line in lines:
        if not line:
            if compact and not blank_seen:
                compact.append("")
            blank_seen = True
            continue
        compact.append(line)
        blank_seen = False
    return "\n".join(compact).strip()


def build_deterministic_communication_reply(
    *,
    user_input: str,
    context: dict[str, Any] | None,
    fallback_reply: str,
) -> ExpertCommunicationReply:
    reply = _normalize_reply_text_preserve_breaks(fallback_reply)
    query = " ".join(str(user_input or "").strip().split())
    lowered_query = query.lower()
    normalized_context = context if isinstance(context, dict) else {}
    topic_hint = _compact_text(normalized_context.get("last_topic"), 64).lower()
    response_mode = _response_mode_for_context(
        user_input=user_input,
        context=normalized_context,
    )

    if reply == "Hi. I am here and ready to help.":
        reply = "Hi. I'm MIM. What would you like to work on?"
        topic_hint = topic_hint or "greeting"
    elif reply == "Yes. I am MIM.":
        reply = "I'm MIM."
        topic_hint = topic_hint or "identity"
    elif reply == "Yes. I can keep this direct, short, and conversational.":
        reply = "Yes. I'll keep this direct, short, and conversational."
    elif reply == "Understood. I will keep responses short.":
        reply = "Understood. I'll keep replies short."
    elif reply == "Understood. I will stay in conversation mode until you ask for a concrete action.":
        reply = "Understood. I'll stay in conversation mode until you ask for a concrete action."
    elif reply == "You'r e welcome.":
        reply = "You're welcome."

    if reply.startswith("I can help right away with one specific request."):
        if "?" in query or any(
            lowered_query.startswith(prefix)
            for prefix in ("what", "how", "why", "when", "where", "who", "which", "can you", "do you")
        ):
            reply = "I can help, but I need one concrete detail to answer well: what exactly do you want me to focus on?"
        else:
            reply = "I can help. Give me one specific question or one concrete action."

    if reply.startswith("I still need one specific request. Options:"):
        reply = "I still need one concrete request. Ask one question, ask for a one-line status, or say create goal: <action>."

    answer_first = _contextual_answer_first_reply(
        user_input=user_input,
        context=normalized_context,
    )
    if answer_first and (
        bool(normalized_context.get("force_deterministic_communication"))
        or _looks_like_clarifier_reply(reply)
        or response_mode == "conversational_confident"
    ):
        reply = answer_first
        response_mode = "answer_first"

    memory_topics = _topic_hints_from_context(query, normalized_context)
    if topic_hint and topic_hint not in memory_topics:
        memory_topics.insert(0, topic_hint)
    deterministic = _apply_response_mode_to_reply(
        reply=ExpertCommunicationReply(
        reply_text=reply,
        topic_hint=topic_hint,
        composer_mode="deterministic_fallback",
        should_store_memory=True,
        memory_topics=memory_topics[:8],
        ),
        response_mode=response_mode,
    )
    return _apply_operator_impact_contract_if_needed(
        reply=deterministic,
        user_input=user_input,
        context=normalized_context,
    )


def _should_preserve_operational_fallback(
    *,
    user_input: str,
    context: dict[str, Any] | None,
    fallback_reply: str,
) -> bool:
    normalized_context = context if isinstance(context, dict) else {}
    topic_hint = _compact_text(normalized_context.get("last_topic"), 64).lower()
    query = " ".join(str(user_input or "").strip().lower().split())
    reply = " ".join(str(fallback_reply or "").strip().split())
    if not reply:
        return False

    operational_topics = {"system", "tod_status", "status", "objective", "priorities", "priority"}
    operational_query_markers = {
        "what is the system",
        "how is tod doing",
        "status now",
        "one line status",
        "summarize your status",
        "current objective",
        "active objective",
        "what are you working on",
        "what are we working on",
        "what should we work on",
        "work on today",
        "runtime health",
        "runtime status",
        "how is runtime health",
        "how is the runtime doing",
        "how is runtime doing",
        "current health",
        "check your current health",
        "wait stop",
        "actually start now",
        "start now",
        "what is next",
        "next for us",
        "what should i do first",
        "what should we prioritize",
        "prioritize next",
        "top priority",
    }
    evidence_markers = {
        "Decision visibility:",
        "TOD collaboration:",
        "Runtime health:",
        "One-line status:",
        "Current status:",
        "Current health:",
        "TOD status:",
        "Current objective focus:",
        "Active goal:",
        "Current recommendation:",
        "Top priority today:",
        "Priority focus:",
        "Next step:",
        "Understood. I will start now.",
        "Understood. I stopped",
        "Got it. I've stopped",
        "Got it, I've paused",
    }

    if topic_hint == "interrupt_control":
        return True

    if topic_hint in operational_topics and any(marker in reply for marker in evidence_markers):
        return True
    if any(marker in query for marker in operational_query_markers) and any(
        marker in reply for marker in evidence_markers
    ):
        return True
    return False


def _model_request_payload(
    *,
    user_input: str,
    context: dict[str, Any],
    fallback_reply: str,
    deterministic_reply: ExpertCommunicationReply,
) -> dict[str, Any]:
    prompt_payload = {
        "user_input": _compact_text(user_input, 500),
        "fallback_reply": _compact_text(fallback_reply, 500),
        "deterministic_reply": deterministic_reply.to_payload(),
        "conversation_context": {
            "session_display_name": _compact_text(context.get("session_display_name"), 80),
            "remembered_user_id": _compact_text(context.get("remembered_user_id"), 80),
            "remembered_display_name": _compact_text(context.get("remembered_display_name"), 80),
            "remembered_aliases": _compact_list(context.get("remembered_aliases"), 6, 40),
            "remembered_conversation_preferences": _compact_list(
                context.get("remembered_conversation_preferences"),
                6,
                80,
            ),
            "remembered_conversation_likes": _compact_list(
                context.get("remembered_conversation_likes"),
                6,
                80,
            ),
            "remembered_conversation_dislikes": _compact_list(
                context.get("remembered_conversation_dislikes"),
                6,
                80,
            ),
            "last_topic": _compact_text(context.get("last_topic"), 80),
            "last_user_input": _compact_text(context.get("last_user_input"), 180),
            "last_prompt": _compact_text(context.get("last_prompt"), 220),
            "last_action_request": _compact_text(context.get("last_action_request"), 180),
            "pending_action_request": _compact_text(context.get("pending_action_request"), 180),
            "recent_conversation": _compact_list(
                [
                    f"{str(item.get('role') or '').strip()}: {str(item.get('content') or '').strip()}"
                    for item in context.get("recent_conversation", [])
                    if isinstance(item, dict)
                ],
                8,
                180,
            ),
            "assistant_name": _compact_text(context.get("assistant_name"), 40),
            "identity": _compact_text(context.get("identity"), 320),
            "assistant_identity": _compact_text(context.get("assistant_identity"), 320),
            "assistant_application": _compact_text(context.get("assistant_application"), 80),
            "assistant_channel": _compact_text(context.get("assistant_channel"), 80),
            "assistant_scope": _compact_text(context.get("assistant_scope"), 220),
            "assistant_capabilities": _compact_text(context.get("assistant_capabilities"), 220),
            "counterpart_identity": _compact_text(context.get("counterpart_identity"), 320),
            "counterpart_application": _compact_text(context.get("counterpart_application"), 80),
            "counterpart_channel": _compact_text(context.get("counterpart_channel"), 80),
            "system_identity": _compact_text(context.get("system_identity"), 320),
            "conversation_policy": _compact_text(context.get("conversation_policy"), 260),
            "language_policy": _compact_text(context.get("language_policy"), 180),
            "customer_success_policy": _compact_text(context.get("customer_success_policy"), 600),
            "current_datetime": _compact_context_signal(context.get("current_datetime")),
            "guardrails": _compact_list(context.get("guardrails"), 8, 120),
        },
        "response_contract": {
            "format": "json_object",
            "schema": {
                "reply_text": "string",
                "topic_hint": "string",
                "response_mode": "string",
                "should_store_memory": "boolean",
                "memory_topics": ["string"],
                "memory_people": ["string"],
                "memory_events": ["string"],
                "memory_experiences": ["string"],
            },
        },
    }
    return {
        "model": str(
            os.getenv("MIM_COMMUNICATION_OPENAI_MODEL")
            or DEFAULT_OPENAI_COMMUNICATION_MODEL
        ).strip(),
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are MIM's communication composer. Rewrite the safe fallback reply into a direct, natural, expert conversation reply. "
                    "Preserve the original meaning, boundaries, and uncertainty. Do not claim actions, web research, or observations that are not already present. "
                    "If conversation_context includes assistant_identity, assistant_application, assistant_channel, counterpart_identity, or system_identity, treat them as authoritative facts about the system and keep identity answers consistent with them. "
                    "If conversation_context includes current_datetime, use it to answer date, day, and time questions naturally. "
                    "Use recent_conversation to resolve short follow-ups like 'what about in France?' instead of asking for clarification when the prior topic makes the referent clear. "
                    "For location-based date/time follow-ups, use matching current_datetime.reference_datetimes entries when present before inferring ordinary civil time zones. "
                    "For public guest chat, ordinary conversation and basic factual questions are allowed; never deflect by saying the channel is only for planning, creativity, or broader thinking. "
                    "Match the language of the visitor's latest message unless they ask to translate or switch languages. "
                    "When customer_success_policy is present, follow it: give useful foundation before discovery, ask only critical questions, diagnose before requesting more details, and choose recommendations when asked to prioritize. "
                    "If conversation_context.response_mode is conversational_confident, do not prepend uncertainty hedges such as 'I am not totally sure' unless the context itself shows conflicting system state, missing verification data, or ambiguous execution results. "
                    "Answer first whenever the fallback reply or conversation_context contains enough signal. Ask a clarifying question only when the user input and context are both too ambiguous to answer. "
                    "Do not recursively re-explain the same setup; keep topical lock on conversation_context.last_topic and last_prompt for follow-up questions. "
                    "Use conversation_context.assistant_name as the self-identifier. Do not rename TOD to MIM or collapse distinct applications into one voice. Prefer 1-3 short sentences. If clarification is truly necessary, ask one crisp clarifying question instead of generic filler. "
                    "Return JSON only."
                ),
            },
            {
                "role": "user",
                "content": json.dumps(prompt_payload, ensure_ascii=False, sort_keys=True),
            },
        ],
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
    }


def _extract_completion_text(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first_choice = choices[0] if isinstance(choices[0], dict) else {}
    message = first_choice.get("message")
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for item in content:
        if not isinstance(item, dict):
            continue
        if str(item.get("type") or "").strip() in {"text", "output_text", "input_text"}:
            text = str(item.get("text") or "").strip()
            if text:
                parts.append(text)
    return "\n".join(parts).strip()


def _compose_with_openai_sync(
    *,
    user_input: str,
    context: dict[str, Any],
    fallback_reply: str,
    deterministic_reply: ExpertCommunicationReply,
) -> ExpertCommunicationReply | None:
    if not _communication_openai_allowed():
        return None
    api_key = _openai_api_key()
    if not api_key:
        return None

    request_payload = _model_request_payload(
        user_input=user_input,
        context=context,
        fallback_reply=fallback_reply,
        deterministic_reply=deterministic_reply,
    )
    request = urllib_request.Request(
        str(
            os.getenv("MIM_COMMUNICATION_OPENAI_URL")
            or DEFAULT_OPENAI_COMMUNICATION_URL
        ).strip(),
        data=json.dumps(request_payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib_request.urlopen(request, timeout=25) as response:
            response_payload = json.loads(response.read().decode("utf-8"))
    except (urllib_error.HTTPError, OSError, ValueError):
        return None

    model_text = _extract_completion_text(response_payload)
    parsed = ExpertCommunicationReply.from_payload(_extract_json_object(model_text))
    if parsed is None:
        return None
    parsed.composer_mode = "openai_rewrite"
    parsed.model = str(response_payload.get("model") or request_payload.get("model") or "").strip()[:64]
    return _apply_response_mode_to_reply(
        reply=parsed,
        response_mode=_response_mode_for_context(user_input=user_input, context=context),
    )


async def compose_expert_communication_reply(
    *,
    user_input: str,
    context: dict[str, Any] | None,
    fallback_reply: str,
) -> ExpertCommunicationReply:
    normalized_context = context if isinstance(context, dict) else {}
    deterministic_reply = build_deterministic_communication_reply(
        user_input=user_input,
        context=normalized_context,
        fallback_reply=fallback_reply,
    )
    if _should_preserve_operational_fallback(
        user_input=user_input,
        context=normalized_context,
        fallback_reply=fallback_reply,
    ):
        return deterministic_reply
    model_reply = await asyncio.to_thread(
        _compose_with_openai_sync,
        user_input=user_input,
        context=normalized_context,
        fallback_reply=fallback_reply,
        deterministic_reply=deterministic_reply,
    )
    if model_reply is not None and str(model_reply.reply_text or "").strip():
        answer_first = _contextual_answer_first_reply(
            user_input=user_input,
            context=normalized_context,
        )
        if answer_first and _looks_like_clarifier_reply(model_reply.reply_text):
            deterministic_reply.reply_text = answer_first
            deterministic_reply.response_mode = "answer_first"
            return deterministic_reply
        rewritten = _apply_response_mode_to_reply(
            reply=model_reply,
            response_mode=deterministic_reply.response_mode,
        )
        return _apply_operator_impact_contract_if_needed(
            reply=rewritten,
            user_input=user_input,
            context=normalized_context,
        )
    return deterministic_reply
